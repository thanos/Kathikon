defmodule Kathikon.Scheduler.BuiltIn.Tick do
  @moduledoc """
  Evaluates recurring cron schedules and enqueues due jobs.

  Ticks every `scheduler_interval` ms (same default as `Kathikon.Scheduler.Promoter`).
  """

  use GenServer

  alias Kathikon.{Config, Scheduler.BuiltIn, Telemetry}

  @tick :tick

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    server_opts = if name in [false, nil], do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, Config.scheduler_interval())
    schedule_tick(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(@tick, state) do
    fired = BuiltIn.fire_due_schedules(DateTime.utc_now())

    if fired > 0 do
      Telemetry.event([:scheduler, :cron_tick], %{fired: fired}, %{})
    end

    schedule_tick(state.interval)
    {:noreply, state}
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), @tick, interval)
  end
end
