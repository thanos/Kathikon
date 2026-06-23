defmodule Kathikon.Scheduler.Quantum.Scheduler do
  @moduledoc """
  Behaviour for the user-configured Quantum scheduler module.

  Implement this behaviour in your app scheduler, or use a test double.
  """

  @callback add_job(term(), keyword()) :: term()
  @callback delete_job(term()) :: :ok | {:error, term()}
  @callback fetch_job(term()) :: {:ok, map()} | {:error, term()}
  @callback update_job(term(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback jobs() :: [map()]
end
