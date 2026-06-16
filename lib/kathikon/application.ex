defmodule Kathikon.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = Kathikon.Mnesia.setup()

    children = [
      {Registry, keys: :unique, name: Kathikon.Registry},
      Kathikon.Queue,
      Kathikon.Scheduler,
      Kathikon.Pruner
    ]

    opts = [strategy: :one_for_one, name: Kathikon.Supervisor]

    with {:ok, supervisor} <- Supervisor.start_link(children, opts) do
      Kathikon.Queue.start_configured()
      {:ok, supervisor}
    end
  end
end
