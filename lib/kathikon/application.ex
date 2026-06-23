defmodule Kathikon.Application do
  @moduledoc """
  Kathikon OTP application supervision tree.

  Starts Mnesia storage, the registry, queue supervisors, the scheduler
  promoter, the pruner, and configured dispatchers when Kathikon is included
  as a dependency.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = Kathikon.Storage.setup()

    children =
      [
        {Registry, keys: :unique, name: Kathikon.Registry},
        Kathikon.Queue,
        Kathikon.QueueControl,
        Kathikon.Scheduler.Promoter,
        Kathikon.Pruner
      ] ++ cron_tick_children()

    opts = [strategy: :one_for_one, name: Kathikon.Supervisor]

    with {:ok, supervisor} <- Supervisor.start_link(children, opts) do
      Kathikon.Queue.start_configured()
      {:ok, supervisor}
    end
  end

  defp cron_tick_children do
    if Application.get_env(:kathikon, :cron_tick, true) do
      [Kathikon.Scheduler.BuiltIn.Tick]
    else
      []
    end
  end
end
