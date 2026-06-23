defmodule Kathikon.Scheduler.Behaviour do
  @moduledoc """
  Behaviour for scheduling adapters.

  Quantum owns clock-based triggering; Kathikon owns durable work.
  """

  @callback schedule_once(module(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback schedule_recurring(module(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback update_schedule(term(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback fetch_schedule(term()) :: {:ok, map()} | {:error, term()}
  @callback cancel_schedule(term()) :: :ok | {:error, term()}
  @callback list_schedules(keyword()) :: {:ok, [map()]} | {:error, term()}
end
