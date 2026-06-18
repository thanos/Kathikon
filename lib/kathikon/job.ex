defmodule Kathikon.Job do
  @moduledoc """
  Represents a durable job obligation in Kathikon.

  Jobs move through explicit states:

    * `:scheduled` — waiting until `scheduled_at` (enqueue delay or `{:sleep, seconds}`)
    * `:available` — ready for a dispatcher to claim
    * `:executing` — currently being processed
    * `:retryable` — failed but will be retried after backoff
    * `:completed` — successfully finished
    * `:cancelled` — explicitly cancelled
    * `:discarded` — exhausted retries or permanently failed

  ## Example

      {:ok, job} = Kathikon.insert(MyWorker, %{"key" => "value"})
      job.id
      job.state       # :available
      job.worker      # MyWorker
      job.args        # %{"key" => "value"}

  See `docs/guides/workers.md` and `docs/reference/modules.md`.
  """

  @enforce_keys [:id, :queue, :worker, :args, :state]
  defstruct [
    :id,
    :queue,
    :worker,
    :args,
    :state,
    priority: 0,
    max_attempts: 20,
    attempts: 0,
    scheduled_at: nil,
    available_at: nil,
    inserted_at: nil,
    started_at: nil,
    completed_at: nil,
    cancelled_at: nil,
    errors: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          queue: atom(),
          worker: module(),
          args: map(),
          state:
            :scheduled
            | :available
            | :executing
            | :retryable
            | :completed
            | :cancelled
            | :discarded,
          priority: non_neg_integer(),
          max_attempts: pos_integer(),
          attempts: non_neg_integer(),
          scheduled_at: DateTime.t() | nil,
          available_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          cancelled_at: DateTime.t() | nil,
          errors: [map()]
        }

  @states [
    :scheduled,
    :available,
    :executing,
    :retryable,
    :completed,
    :cancelled,
    :discarded
  ]

  @doc false
  def states, do: @states

  @doc """
  Builds a new job from worker module, args, and options.

  Prefer `Kathikon.insert/3` for enqueueing — it persists the job and
  starts the queue dispatcher.

  ## Options

  Same as `Kathikon.insert/3`: `:queue`, `:priority`, `:max_attempts`,
  `:schedule_in`, `:schedule_at`.

  ## Example

      job = Kathikon.Job.build(MyWorker, %{"x" => 1}, queue: :default)
      job.state  # :available
  """
  @spec build(module(), map(), keyword()) :: t()
  def build(worker, args, opts) do
    now = DateTime.utc_now()
    queue = Keyword.get(opts, :queue, :default)
    priority = Keyword.get(opts, :priority, 0)
    max_attempts = Keyword.get(opts, :max_attempts, Kathikon.Config.max_attempts())

    {state, scheduled_at, available_at} = schedule_fields(opts, now)

    %__MODULE__{
      id: generate_id(),
      queue: queue,
      worker: worker,
      args: args,
      state: state,
      priority: priority,
      max_attempts: max_attempts,
      attempts: 0,
      scheduled_at: scheduled_at,
      available_at: available_at,
      inserted_at: now,
      errors: []
    }
  end

  @doc """
  Returns true when the job can be claimed for execution at `now`.

  A job is claimable when its state is `:available` or `:retryable` and
  `available_at` is not in the future.

  ## Example

      job = Kathikon.Job.build(MyWorker, %{}, schedule_in: 60)
      Kathikon.Job.claimable?(job, DateTime.utc_now())  # false

      {:ok, job} = Kathikon.fetch(job_id)
      Kathikon.Job.claimable?(job, DateTime.utc_now())  # true when due
  """
  @spec claimable?(t(), DateTime.t()) :: boolean()
  def claimable?(%__MODULE__{state: state, available_at: available_at}, now) do
    state in [:available, :retryable] and DateTime.compare(available_at, now) != :gt
  end

  @doc """
  Computes exponential backoff in seconds for the given attempt number.

  Formula: `min(attempt² × 5, 86400)` seconds (minimum 1 for attempt ≤ 0).

  ## Examples

      Kathikon.Job.backoff_seconds(1)  # 5
      Kathikon.Job.backoff_seconds(2)  # 20
      Kathikon.Job.backoff_seconds(3)  # 45
  """
  @spec backoff_seconds(non_neg_integer()) :: non_neg_integer()
  def backoff_seconds(attempt) when attempt <= 0, do: 1

  def backoff_seconds(attempt) do
    min(trunc(:math.pow(attempt, 2) * 5), 86_400)
  end

  @doc false
  def to_record(%__MODULE__{} = job) do
    {:kathikon_jobs, job.id, :erlang.term_to_binary(job)}
  end

  @doc """
  Deserializes a job payload written by `to_record/1`.

  Uses `:erlang.binary_to_term/2` with `[:safe]`. Payloads are produced
  internally by Kathikon on the same node; this is not an untrusted boundary
  in Phase 1.
  """
  @spec decode_payload(binary()) :: t()
  def decode_payload(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary, [:safe])
  end

  @doc false
  def from_record({:kathikon_jobs, id, binary}) when is_binary(binary) do
    job = decode_payload(binary)
    %{job | id: id}
  end

  defp schedule_fields(opts, now) do
    cond do
      schedule_at = Keyword.get(opts, :schedule_at) ->
        if DateTime.compare(schedule_at, now) == :gt do
          {:scheduled, schedule_at, schedule_at}
        else
          {:available, schedule_at, now}
        end

      schedule_in = Keyword.get(opts, :schedule_in) ->
        at = DateTime.add(now, schedule_in, :second)
        {:scheduled, at, at}

      true ->
        {:available, now, now}
    end
  end

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
end
