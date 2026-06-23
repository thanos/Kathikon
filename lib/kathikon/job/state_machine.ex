defmodule Kathikon.Job.StateMachine do
  @moduledoc """
  Validates job state transitions for Kathikon v0.2.0.

  Invalid transitions return `{:error, {:invalid_transition, from, to}}`.
  Terminal states reject all outbound transitions.

  ## Allowed transitions

      scheduled -> available
      scheduled -> cancelled
      available -> claimed
      available -> cancelled
      claimed -> running
      claimed -> cancelled
      running -> completed
      running -> retryable
      running -> failed
      running -> waiting_for_children
      waiting_for_children -> completed
      waiting_for_children -> failed
      retryable -> scheduled
      retryable -> available
      failed -> dead
      failed -> discarded

  Claiming also moves `:retryable` jobs to `:claimed` when they are due.
  """

  @transitions %{
    scheduled: [:available, :cancelled],
    available: [:claimed, :cancelled],
    claimed: [:running, :cancelled],
    running: [:completed, :retryable, :failed, :waiting_for_children, :discarded, :scheduled],
    waiting_for_children: [:completed, :failed],
    retryable: [:scheduled, :available, :claimed],
    failed: [:dead, :discarded],
    completed: [],
    discarded: [],
    cancelled: [],
    dead: []
  }

  @doc """
  Returns true when `to` is allowed from `from`.
  """
  @spec allowed?(atom(), atom()) :: boolean()
  def allowed?(from, to) do
    from = normalize(from)
    to = normalize(to)
    to in Map.get(@transitions, from, [])
  end

  @doc """
  Validates a transition. Returns `:ok` or `{:error, {:invalid_transition, from, to}}`.
  """
  @spec transition(atom(), atom()) :: :ok | {:error, {:invalid_transition, atom(), atom()}}
  def transition(from, to) do
    from = normalize(from)
    to = normalize(to)

    if allowed?(from, to) do
      :ok
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  @doc """
  Returns the list of states reachable from `state`.
  """
  @spec reachable_from(atom()) :: [atom()]
  def reachable_from(state), do: Map.get(@transitions, normalize(state), [])

  @doc """
  Returns true when the job is in a terminal state.
  """
  @spec terminal?(atom()) :: boolean()
  def terminal?(state) do
    normalize(state) in [:completed, :discarded, :cancelled, :dead]
  end

  @doc """
  Returns all supported states.
  """
  @spec states() :: [atom()]
  def states, do: Map.keys(@transitions)

  @doc false
  def normalize(:executing), do: :running
  def normalize(state) when is_atom(state), do: state
end
