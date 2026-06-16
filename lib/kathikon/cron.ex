defmodule Kathikon.Cron do
  @moduledoc """
  Cron-based job scheduling.

  This module is a placeholder for Phase 3 (Production Scheduling). Cron jobs
  will be stored in Mnesia and evaluated by a dedicated scheduler process
  that inserts jobs into the durable queue at the appropriate times.
  """

  @doc """
  Registers a cron schedule. Not yet implemented.
  """
  @spec insert(module(), map(), keyword()) :: {:error, :not_implemented}
  def insert(_worker, _args, _opts \\ []) do
    {:error, :not_implemented}
  end
end
