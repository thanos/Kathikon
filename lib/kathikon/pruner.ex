defmodule Kathikon.Pruner do
  @moduledoc """
  Removes terminal jobs past the retention period.

  Deletes `:completed`, `:cancelled`, and `:discarded` jobs older than
  `retention_period`. Ticks every `prune_interval` ms.

  Mnesia is coordination storage, not long-term history — export metrics
  via telemetry for durable audit trails.

  See `docs/guides/configuration.md`.
  """

  use GenServer

  alias Kathikon.{Storage, Telemetry}

  @tick :tick

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, Kathikon.Config.prune_interval())
    schedule_tick(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(@tick, state) do
    now = DateTime.utc_now()
    retention = Kathikon.Config.retention_period()
    cutoff = DateTime.add(now, -retention, :millisecond)
    pruned = prune_jobs(cutoff)

    if pruned > 0 do
      Telemetry.event([:pruner, :tick], %{pruned: pruned}, %{})
    end

    schedule_tick(state.interval)
    {:noreply, state}
  end

  defp prune_jobs(cutoff) do
    Storage.prunable_jobs(cutoff)
    |> Enum.reduce(0, fn job, count ->
      Storage.delete(job.id)

      Telemetry.event([:job, :prune], %{}, %{
        queue: job.queue,
        job_id: job.id,
        state: job.state
      })

      count + 1
    end)
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), @tick, interval)
  end
end
