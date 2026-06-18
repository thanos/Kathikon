defmodule Kathikon.Scheduler do
  @moduledoc """
  Promotes scheduled jobs to `:available` when their time arrives.

  Ticks every `scheduler_interval` ms. Promotion runs in a single Mnesia
  transaction via the configured storage module (default `Kathikon.Storage`).

  ## `start_link/1` options

    * `:interval` — tick period in ms (default from `Kathikon.Config`)
    * `:storage` — module implementing `Kathikon.Backend.Storage` callbacks
    * `:name` — registered name (default `Kathikon.Scheduler`; use `false` in tests)

  See `docs/guides/scheduling.md`.
  """

  use GenServer

  alias Kathikon.{Storage, Telemetry}

  @tick :tick

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    server_opts = if name in [false, nil], do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, Kathikon.Config.scheduler_interval())
    storage = Keyword.get(opts, :storage, Storage)
    schedule_tick(interval)
    {:ok, %{interval: interval, storage: storage}}
  end

  @impl true
  def handle_info(@tick, state) do
    now = DateTime.utc_now()
    promoted = state.storage.promote_scheduled(now)

    if promoted > 0 do
      Telemetry.event([:scheduler, :tick], %{promoted: promoted}, %{})
    end

    schedule_tick(state.interval)
    {:noreply, state}
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), @tick, interval)
  end
end
