defmodule Kathikon.Dispatcher do
  @moduledoc """
  Claims and executes jobs for a single queue.

  The dispatcher polls Mnesia for available jobs and spawns tasks up to the
  queue's concurrency limit. Each job is executed inside the worker module's
  `perform/1` callback.
  """

  use GenServer

  alias Kathikon.{Job, Storage, Telemetry}

  @poll_message :poll

  def start_link(opts) do
    queue = Keyword.fetch!(opts, :queue)
    GenServer.start_link(__MODULE__, opts, name: via(queue))
  end

  @doc false
  def via(queue), do: {:via, Registry, {Kathikon.Registry, {:dispatcher, queue}}}

  @impl true
  def init(opts) do
    queue = Keyword.fetch!(opts, :queue)
    config = Keyword.fetch!(opts, :config)
    poll_interval = Keyword.get(opts, :poll_interval, Kathikon.Config.poll_interval())

    state = %{
      queue: queue,
      config: config,
      concurrency: Keyword.get(config, :concurrency, 10),
      poll_interval: poll_interval,
      running: %{}
    }

    schedule_poll(poll_interval)
    {:ok, state}
  end

  @impl true
  def handle_info(@poll_message, state) do
    state = maybe_claim_jobs(state)
    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    {:noreply, %{state | running: Map.delete(state.running, ref)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, %{state | running: Map.delete(state.running, ref)}}
  end

  defp maybe_claim_jobs(state) do
    slots = state.concurrency - map_size(state.running)

    if slots > 0 do
      claim_and_run(state, slots)
    else
      state
    end
  end

  defp claim_and_run(state, slots) do
    now = DateTime.utc_now()

    Enum.reduce(1..slots, state, fn _, acc ->
      case Storage.claim(acc.queue, now) do
        {:ok, job} ->
          Telemetry.event([:dispatcher, :poll], %{count: 1}, %{queue: acc.queue, job_id: job.id})
          run_job(acc, job)

        :not_found ->
          acc

        {:error, _} ->
          acc
      end
    end)
  end

  defp run_job(state, job) do
    parent = self()

    task =
      Task.async(fn ->
        execute_job(job, parent)
      end)

    %{state | running: Map.put(state.running, task.ref, task.pid)}
  end

  defp execute_job(job, dispatcher) do
    start_time = System.monotonic_time()

    Telemetry.event([:job, :start], %{}, %{
      queue: job.queue,
      job_id: job.id,
      worker: job.worker,
      attempt: job.attempts + 1
    })

    result =
      try do
        job.worker.perform(job)
      rescue
        exception ->
          {:error, {:exception, exception, __STACKTRACE__}}
      catch
        kind, reason ->
          {:error, {kind, reason}}
      end

    duration = System.monotonic_time() - start_time

    GenServer.cast(dispatcher, {:job_finished, job, result, duration})
  end

  @impl true
  def handle_cast({:job_finished, job, result, duration}, state) do
    now = DateTime.utc_now()
    attempt = job.attempts + 1

    {updated, event_suffix, extra_metadata} =
      case result do
        :ok ->
          job = %{
            job
            | state: :completed,
              attempts: attempt,
              completed_at: now
          }

          {job, [:job, :stop], %{result: :ok}}

        {:error, reason} ->
          handle_failure(job, attempt, reason, now)
      end

    Storage.update(updated)

    metadata =
      Map.merge(
        %{
          queue: job.queue,
          job_id: job.id,
          worker: job.worker,
          attempt: attempt,
          duration: duration
        },
        extra_metadata
      )

    Telemetry.event(event_suffix, %{duration: duration}, metadata)

    {:noreply, state}
  end

  defp handle_failure(job, attempt, reason, now) do
    error = %{
      at: DateTime.to_iso8601(now),
      attempt: attempt,
      reason: inspect(reason)
    }

    errors = job.errors ++ [error]

    if attempt >= job.max_attempts do
      job = %{
        job
        | state: :discarded,
          attempts: attempt,
          completed_at: now,
          errors: errors
      }

      {job, [:job, :discard], %{result: :discarded, reason: reason}}
    else
      backoff = Job.backoff_seconds(attempt)
      available_at = DateTime.add(now, backoff, :second)

      job = %{
        job
        | state: :retryable,
          attempts: attempt,
          available_at: available_at,
          errors: errors
      }

      {job, [:job, :retry], %{result: :retry, reason: reason, backoff: backoff}}
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), @poll_message, interval)
  end
end
