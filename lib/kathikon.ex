defmodule Kathikon do
  @moduledoc """
  BEAM-native durable job queue and task execution platform.

  Kathikon (Greek: καθήκον — duty, obligation) treats jobs as durable
  obligations that must eventually be fulfilled: completed, retried,
  cancelled, or discarded — but never silently lost.

  ## Guides

    * [Quick start](docs/guides/quick-start.md)
    * [Workers](docs/guides/workers.md)
    * [Queues & concurrency](docs/guides/queues-and-concurrency.md)
    * [Scheduling](docs/guides/scheduling.md)
    * [Retries & errors](docs/guides/retries-and-errors.md)
    * [Module reference](docs/reference/modules.md)

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
    * `:max_attempts` — retry limit (default from config, `20`)
    * `:schedule_in` — delay in seconds before the job becomes available
    * `:schedule_at` — `DateTime` when the job becomes available

  ## Telemetry

  Kathikon emits `[:kathikon, ...]` telemetry events for job lifecycle,
  scheduler ticks, and pruning. See `Kathikon.Telemetry` and
  `docs/guides/telemetry-and-observability.md`.
  """

  alias Kathikon.{Job, Queue, Storage, Telemetry}

  @doc """
  Inserts a job into the durable queue.

  Starts the queue dispatcher if it is not already running.
  Emits `[:kathikon, :job, :insert]`.

  ## Options

    * `:queue` — target queue atom (default `:default`)
    * `:priority` — non-negative integer, higher claims first (default `0`)
    * `:max_attempts` — retry limit (default from `Kathikon.Config`)
    * `:schedule_in` — seconds until the job becomes available
    * `:schedule_at` — `DateTime` when the job becomes available

  ## Examples

      {:ok, job} = Kathikon.insert(MyWorker, %{"id" => "1"})

      {:ok, job} =
        Kathikon.insert(EmailWorker, %{"to" => "u@example.com"},
          queue: :emails,
          priority: 5,
          max_attempts: 10
        )

      {:ok, job} =
        Kathikon.insert(DigestWorker, %{}, schedule_in: 3600)

  ## Returns

    * `{:ok, job}` — job persisted; `job.state` is `:available` or `:scheduled`
    * `{:error, reason}` — storage failure (e.g. duplicate id)
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
  Cancels a job that has not yet reached a terminal success state.

  ## Cancellable states

    * `:scheduled`, `:available`, `:retryable` — returns `{:ok, job}` with `state: :cancelled`
    * `:executing` — returns `{:error, :executing}` (Phase 1 does not interrupt running tasks)
    * `:completed`, `:cancelled`, `:discarded` — returns `{:error, {:invalid_state, state}}`

  ## Example

      {:ok, job} =
        Kathikon.insert(NewsletterWorker, %{}, schedule_in: 86_400)

      {:ok, cancelled} = Kathikon.cancel(job.id)
      cancelled.state  # :cancelled
  """
  @spec cancel(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def cancel(job_id) when is_binary(job_id) do
    with {:ok, job} <- Storage.fetch(job_id),
         :ok <- validate_cancellable(job) do
      cancel_job(job)
    end
  end

  defp validate_cancellable(%Job{state: state})
       when state in [:completed, :cancelled, :discarded] do
    {:error, {:invalid_state, state}}
  end

  defp validate_cancellable(%Job{state: :executing}), do: {:error, :executing}
  defp validate_cancellable(%Job{}), do: :ok

  defp cancel_job(job) do
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

  @doc """
  Fetches a job by id.

  ## Example

      {:ok, job} = Kathikon.fetch(job_id)
      job.state
      job.attempts

  Returns `{:error, :not_found}` if the job was pruned or never existed.
  """
  @spec fetch(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def fetch(job_id), do: Storage.fetch(job_id)

  @doc """
  Lists all jobs currently in storage.

  Intended for inspection, debugging, and tests — not for production dashboards.

  ## Example

      Kathikon.all()
      |> Enum.filter(&(&1.state == :retryable))
  """
  @spec all() :: [Job.t()]
  def all, do: Storage.all()

  @doc """
  Ensures a dispatcher is running for the given queue.

  Called automatically by `insert/3`. Use directly when starting
  a queue before any jobs are enqueued.

  ## Example

      :ok = Kathikon.start_queue(:imports)
  """
  @spec start_queue(atom()) :: :ok
  def start_queue(queue) when is_atom(queue), do: Queue.ensure_started(queue)
end
