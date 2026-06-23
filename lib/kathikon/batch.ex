defmodule Kathikon.Batch do
  @moduledoc """
  Simple parent/child batch workflows for fan-out/fan-in.

  The parent job moves to `:waiting_for_children` without blocking a BEAM process.
  When the batch completes, an explicit continuation job is enqueued.

  ## Examples

      {:ok, parent} = Kathikon.Storage.insert(parent_job)

      {:ok, batch} =
        Kathikon.Batch.start(parent.id, [
          {ChildWorker, %{"id" => 1}, [queue: :default]},
          {ChildWorker, %{"id" => 2}, [queue: :default]}
        ], on_complete: {ReportWorker, %{"parent_id" => parent.id}})

      {:ok, %{status: :running}} = Kathikon.Batch.status(batch.batch_id)

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

  ## Examples

      {:ok, batch} =
        Kathikon.Batch.start(parent_job_id, [
          {ProcessRowWorker, %{"row" => 1}, []},
          {ProcessRowWorker, %{"row" => 2}, []}
        ], on_complete: {SummarizeWorker, %{}})
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

          Job.build(
            worker,
            args,
            Keyword.merge(child_opts, parent_job_id: parent_job_id, batch_id: batch_id)
          )
        end)

      for job <- child_jobs, do: :ok = Kathikon.Queue.ensure_started(job.queue)

      batch_attrs = %{
        batch_id: batch_id,
        status: :running,
        success_count: 0,
        failure_count: 0,
        cancelled_count: 0,
        success_policy: success_policy,
        on_complete: on_complete,
        created_at: now,
        completed_at: nil,
        metadata: %{}
      }

      case Storage.start_batch(parent_job_id, child_jobs, batch_attrs) do
        {:ok, batch} ->
          Telemetry.event([:batch, :started], %{children: length(batch.child_job_ids)}, %{
            batch_id: batch_id,
            parent_job_id: parent_job_id
          })

          {:ok, batch}

        other ->
          other
      end
    end
  end

  @doc """
  Returns batch status by batch id.

  ## Examples

      {:ok, batch} = Kathikon.Batch.status(batch_id)
      batch.status
      #=> :running
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, term()}
  def status(batch_id) do
    case Storage.fetch_batch(batch_id) do
      {:ok, batch} -> {:ok, batch}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Lists child job ids for a batch.

  ## Examples

      {:ok, child_ids} = Kathikon.Batch.children(batch_id)
  """
  @spec children(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def children(batch_id) do
    with {:ok, batch} <- status(batch_id) do
      {:ok, batch.child_job_ids}
    end
  end

  @doc """
  Returns results for completed child jobs in a batch.

  ## Examples

      {:ok, results} = Kathikon.Batch.results(batch_id)

      Enum.filter(results, &(&1.state == :completed))
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

  ## Examples

      {:ok, retried} = Kathikon.Batch.retry_failed(batch_id)
      length(retried)
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

      {:ok, _} = Storage.write_batch(updated)
      {:ok, retried}
    end
  end

  @doc false
  def handle_child_finished(child_job) do
    case Storage.record_batch_child_finished(child_job) do
      {:ok, :ignored} -> :ok
      {:ok, :already_finished} -> :ok
      {:ok, :pending, _batch} -> :ok
      {:ok, :complete, batch, parent} -> complete_batch(batch, parent)
      {:ok, :fail, batch, parent} -> fail_batch(batch, parent)
      _ -> :ok
    end
  end

  defp complete_batch(batch, parent) do
    now = DateTime.utc_now()

    {:ok, _} =
      Storage.complete_job(parent.id, %{batch_id: batch.batch_id}, %{
        batch_id: batch.batch_id
      })

    completed_batch = %{batch | status: :completed, completed_at: now}
    {:ok, _} = Storage.write_batch(completed_batch)

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
        attempt: parent.max_attempts
      })

    failed_batch = %{batch | status: :failed, completed_at: DateTime.utc_now()}
    {:ok, _} = Storage.write_batch(failed_batch)
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
