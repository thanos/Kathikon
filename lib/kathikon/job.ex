defmodule Kathikon.Job do
  @moduledoc """
  Represents a durable job obligation in Kathikon.

  Jobs move through explicit states:

    * `:scheduled` — waiting until `scheduled_at`
    * `:available` — ready for a worker to claim
    * `:executing` — currently being processed
    * `:retryable` — failed but will be retried after backoff
    * `:completed` — successfully finished
    * `:cancelled` — explicitly cancelled
    * `:discarded` — exhausted retries or permanently failed
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
  Returns true when the job can be claimed for execution.
  """
  @spec claimable?(t(), DateTime.t()) :: boolean()
  def claimable?(%__MODULE__{state: state, available_at: available_at}, now) do
    state in [:available, :retryable] and DateTime.compare(available_at, now) != :gt
  end

  @doc """
  Computes exponential backoff in seconds for the given attempt number.
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

  @doc false
  def from_record({:kathikon_jobs, id, binary}) when is_binary(binary) do
    job = :erlang.binary_to_term(binary)
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
