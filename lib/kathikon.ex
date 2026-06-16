defmodule Kathikon do
  @moduledoc """
  BEAM-native durable job queue and task execution platform.

  Kathikon (Greek: καθήκον — duty, obligation) treats jobs as durable
  obligations that must eventually be fulfilled: completed, retried,
  cancelled, or discarded — but never silently lost.

  ## Quick start

  Define a worker:

      defmodule MyApp.EmailWorker do
        use Kathikon.Worker

        @impl true
        def perform(%Kathikon.Job{args: %{"email" => email}}) do
          MyApp.Mailer.deliver(email)
          :ok
        end
      end

  Enqueue a job:

      {:ok, job} = Kathikon.insert(MyApp.EmailWorker, %{"email" => "a@b.com"})

  Configure queues in `config/config.exs`:

      config :kathikon,
        queues: [
          default: [concurrency: 10],
          emails: [concurrency: 5]
        ]

  ## Job options

    * `:queue` — target queue (default `:default`)
    * `:priority` — higher runs first (default `0`)
    * `:max_attempts` — retry limit (default `20`)
    * `:schedule_in` — delay in seconds before the job becomes available
    * `:schedule_at` — `DateTime` when the job becomes available

  ## Telemetry

  Kathikon emits `[:kathikon, ...]` telemetry events for job lifecycle,
  scheduler ticks, and pruning. See `Kathikon.Telemetry` for details.
  """

  alias Kathikon.{Job, Queue, Storage, Telemetry}

  @doc """
  Inserts a job into the durable queue.

  Returns `{:ok, job}` on success.
  """
  @spec insert(module(), map(), keyword()) :: {:ok, Job.t()} | {:error, term()}
  def insert(worker, args, opts \\ []) when is_atom(worker) and is_map(args) do
    job = Job.build(worker, args, opts)
    :ok = Queue.ensure_started(job.queue)

    with {:ok, job} <- Storage.insert(job) do
      Telemetry.event([:job, :insert], %{}, %{
        queue: job.queue,
        job_id: job.id,
        worker: worker,
        state: job.state
      })

      {:ok, job}
    end
  end

  @doc """
  Cancels a job that has not yet completed.

  Jobs in `:executing` cannot be cancelled in Phase 1.
  """
  @spec cancel(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def cancel(job_id) when is_binary(job_id) do
    with {:ok, job} <- Storage.fetch(job_id) do
      if job.state in [:completed, :cancelled, :discarded] do
        {:error, {:invalid_state, job.state}}
      else
        if job.state == :executing do
          {:error, :executing}
        else
          now = DateTime.utc_now()
          job = %{job | state: :cancelled, cancelled_at: now}

          with {:ok, job} <- Storage.update(job) do
            Telemetry.event([:job, :cancel], %{}, %{
              queue: job.queue,
              job_id: job.id
            })

            {:ok, job}
          end
        end
      end
    end
  end

  @doc """
  Fetches a job by id.
  """
  @spec fetch(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def fetch(job_id), do: Storage.fetch(job_id)

  @doc """
  Lists all jobs. Intended for inspection and testing.
  """
  @spec all() :: [Job.t()]
  def all, do: Storage.all()

  @doc """
  Ensures a queue dispatcher is running.
  """
  @spec start_queue(atom()) :: :ok
  def start_queue(queue) when is_atom(queue), do: Queue.ensure_started(queue)
end
