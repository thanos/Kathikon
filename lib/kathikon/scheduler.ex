defmodule Kathikon.Scheduler do
  @moduledoc """
  Promotes scheduled jobs to the available state when their time arrives.

  Jobs inserted with `schedule_at` or `schedule_in` begin in `:scheduled`.
  The scheduler periodically scans for jobs whose `scheduled_at` has passed
  and transitions them to `:available`.
  """

  use GenServer

  alias Kathikon.{Storage, Telemetry}

  @tick :tick

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, Kathikon.Config.scheduler_interval())
    schedule_tick(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(@tick, state) do
    now = DateTime.utc_now()
    promoted = promote_scheduled(now)

    if promoted > 0 do
      Telemetry.event([:scheduler, :tick], %{promoted: promoted}, %{})
    end

    schedule_tick(state.interval)
    {:noreply, state}
  end

  defp promote_scheduled(now) do
    Storage.promote_scheduled(now)
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), @tick, interval)
  end
end
