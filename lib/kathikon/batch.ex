defmodule Kathikon.Batch do
  @moduledoc """
  Simple parent/child batch workflows for fan-out/fan-in.

  The parent job moves to `:waiting_for_children` without blocking a BEAM process.
  When the batch completes, an explicit continuation job is enqueued.

  See `docs/batches.md`.
  """

  alias Kathikon.{Job, Storage, Telemetry}

  @type child_spec :: {module(), term(), keyword()} | map()

  @doc """
  Starts a batch from a parent job, enqueueing child jobs.

  ## Options

    * `:on_complete` — `{WorkerModule, args}` continuation when batch succeeds
    * `:success_policy` — `:all_succeeded` (default), `{:at_least, n}`, or `:allow_partial`
    * `:queue` — queue for child jobs
  """
  @spec start(String.t(), [child_spec()], keyword()) :: {:ok, map()} | {:error, term()}
  def start(parent_job_id, child_specs, opts \\ []) when is_list(child_specs) do
    with {:ok, parent} <- Storage.fetch(parent_job_id) do
      batch_id = generate_id()
      queue = Keyword.get(opts, :queue, parent.queue)
      success_policy = Keyword.get(opts, :success_policy, :all_succeeded)
      on_complete = Keyword.get(opts, :on_complete)
      now = DateTime.utc_now()

      child_jobs =
        Enum.map(child_specs, fn spec ->
          {worker, args, child_opts} = normalize_spec(spec, queue)

          job =
            Job.build(
              worker,
              args,
              Keyword.merge(child_opts, parent_job_id: parent_job_id, batch_id: batch_id)
            )

          job
        end)

      with {:ok, _} <- transition_parent_waiting(parent, batch_id),
           {:ok, child_ids} <- insert_children(child_jobs),
           {:ok, batch} <-
             create_batch(batch_id, parent_job_id, child_ids, success_policy, on_complete, now) do
        Telemetry.event([:batch, :started], %{children: length(child_ids)}, %{
          batch_id: batch_id,
          parent_job_id: parent_job_id
        })

        Storage.insert_history_event(parent_job_id, %{
          id: generate_id(),
          job_id: parent_job_id,
          event: :batch_started,
          from_state: parent.state,
          to_state: :waiting_for_children,
          metadata: %{batch_id: batch_id, child_count: length(child_ids)},
          inserted_at: now
        })

        {:ok, batch}
      end
    end
  end

  @doc """
  Returns batch status by batch id (same as parent job id lookup via batch record).
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, term()}
  def status(batch_id) do
    case Storage.Mnesia.fetch_batch(batch_id) do
      {:ok, batch} -> {:ok, batch}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Lists child job ids for a batch.
  """
  @spec children(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def children(batch_id) do
    with {:ok, batch} <- status(batch_id) do
      {:ok, batch.child_job_ids}
    end
  end

  @doc """
  Returns results for completed child jobs in a batch.
  """
  @spec results(String.t()) :: {:ok, [map()]} | {:error, term()}
  def results(batch_id) do
    with {:ok, batch} <- status(batch_id),
         {:ok, jobs} <- fetch_child_jobs(batch.child_job_ids) do
      results =
        Enum.map(jobs, fn job ->
          %{job_id: job.id, state: job.state, result: job.result, error: job.last_error}
        end)

      {:ok, results}
    end
  end

  @doc """
  Retries failed children in a batch.
  """
  @spec retry_failed(String.t()) :: {:ok, [Job.t()]} | {:error, term()}
  def retry_failed(batch_id) do
    with {:ok, batch} <- status(batch_id),
         {:ok, jobs} <- fetch_child_jobs(batch.child_job_ids) do
      retried =
        jobs
        |> Enum.filter(&(&1.state in [:failed, :dead, :retryable]))
        |> Enum.map(fn job ->
          {:ok, retried} = Storage.retry_job(job.id, [])
          retried
        end)

      updated = %{
        batch
        | pending_count: batch.pending_count + length(retried),
          failure_count: max(0, batch.failure_count - length(retried)),
          status: :running
      }

      {:ok, _} = Storage.Mnesia.write_batch(updated)
      {:ok, retried}
    end
  end

  @doc false
  def handle_child_finished(child_job) do
    with batch_id when not is_nil(batch_id) <- child_job.batch_id,
         {:ok, batch} <- status(batch_id),
         {:ok, parent} <- Storage.fetch(batch.parent_job_id) do
      {batch, parent} = update_counters(batch, parent, child_job)
      maybe_complete_batch(batch, parent)
    else
      _ -> :ok
    end
  end

  defp transition_parent_waiting(parent, batch_id) do
    metadata = %{batch_id: batch_id}

    Storage.update_job(parent.id, %{
      state: :waiting_for_children,
      batch_id: batch_id
    })
    |> tap(fn
      {:ok, _} ->
        Storage.insert_history_event(parent.id, %{
          id: generate_id(),
          job_id: parent.id,
          event: :child_created,
          from_state: parent.state,
          to_state: :waiting_for_children,
          metadata: metadata,
          inserted_at: DateTime.utc_now()
        })

      _ ->
        :ok
    end)
  end

  defp insert_children(jobs) do
    ids =
      Enum.map(jobs, fn job ->
        :ok = Kathikon.Queue.ensure_started(job.queue)
        {:ok, inserted} = Storage.insert(job)

        Storage.insert_history_event(inserted.id, %{
          id: generate_id(),
          job_id: inserted.id,
          event: :child_created,
          from_state: nil,
          to_state: inserted.state,
          metadata: %{parent_job_id: job.parent_job_id, batch_id: job.batch_id},
          inserted_at: DateTime.utc_now()
        })

        inserted.id
      end)

    {:ok, ids}
  end

  defp create_batch(batch_id, parent_job_id, child_ids, success_policy, on_complete, now) do
    batch = %{
      batch_id: batch_id,
      parent_job_id: parent_job_id,
      child_job_ids: child_ids,
      status: :running,
      pending_count: length(child_ids),
      success_count: 0,
      failure_count: 0,
      cancelled_count: 0,
      success_policy: success_policy,
      on_complete: on_complete,
      created_at: now,
      completed_at: nil,
      metadata: %{}
    }

    Storage.Mnesia.write_batch(batch)
  end

  defp update_counters(batch, parent, child) do
    batch =
      case child.state do
        :completed ->
          %{
            batch
            | pending_count: batch.pending_count - 1,
              success_count: batch.success_count + 1
          }

        state when state in [:failed, :dead, :discarded] ->
          %{
            batch
            | pending_count: batch.pending_count - 1,
              failure_count: batch.failure_count + 1
          }

        :cancelled ->
          %{
            batch
            | pending_count: batch.pending_count - 1,
              cancelled_count: batch.cancelled_count + 1
          }

        _ ->
          batch
      end

    {:ok, _} = Storage.Mnesia.write_batch(batch)
    {batch, parent}
  end

  defp maybe_complete_batch(batch, parent) do
    if batch.pending_count > 0 do
      :ok
    else
      success? = batch_succeeded?(batch)

      if success? do
        complete_batch(batch, parent)
      else
        fail_batch(batch, parent)
      end
    end
  end

  defp batch_succeeded?(%{success_policy: :all_succeeded, failure_count: 0, cancelled_count: 0}),
    do: true

  defp batch_succeeded?(%{success_policy: :allow_partial, success_count: s}) when s > 0, do: true

  defp batch_succeeded?(%{success_policy: {:at_least, n}, success_count: s}), do: s >= n
  defp batch_succeeded?(_), do: false

  defp complete_batch(batch, parent) do
    now = DateTime.utc_now()

    {:ok, _} =
      Storage.complete_job(parent.id, %{batch_id: batch.batch_id}, %{
        batch_id: batch.batch_id
      })

    completed_batch = %{batch | status: :completed, completed_at: now}
    {:ok, _} = Storage.Mnesia.write_batch(completed_batch)

    _ = enqueue_continuation(batch)

    Telemetry.event([:batch, :completed], %{success_count: batch.success_count}, %{
      batch_id: batch.batch_id,
      parent_job_id: parent.id
    })

    _ =
      Storage.insert_history_event(parent.id, %{
        id: generate_id(),
        job_id: parent.id,
        event: :batch_completed,
        from_state: :waiting_for_children,
        to_state: :completed,
        metadata: %{batch_id: batch.batch_id},
        inserted_at: now
      })
  end

  defp fail_batch(batch, parent) do
    {:ok, _} =
      Storage.fail_job(parent.id, :batch_failed, %{
        batch_id: batch.batch_id,
        attempt: parent.attempts + 1
      })

    failed_batch = %{batch | status: :failed, completed_at: DateTime.utc_now()}
    {:ok, _} = Storage.Mnesia.write_batch(failed_batch)
  end

  defp enqueue_continuation(%{on_complete: {worker, args}}) when is_atom(worker) do
    Kathikon.insert(worker, args || %{})
  end

  defp enqueue_continuation(_), do: :ok

  defp fetch_child_jobs(ids) do
    jobs =
      Enum.map(ids, fn id ->
        {:ok, job} = Storage.fetch(id)
        job
      end)

    {:ok, jobs}
  end

  defp normalize_spec({worker, args, opts}, default_queue) do
    {worker, args || %{}, Keyword.put_new(opts || [], :queue, default_queue)}
  end

  defp normalize_spec(%{worker: worker} = spec, default_queue) do
    {
      worker,
      Map.get(spec, :args, %{}),
      [
        queue: Map.get(spec, :queue, default_queue),
        max_attempts: Map.get(spec, :max_attempts, Kathikon.Config.max_attempts())
      ]
    }
  end

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
