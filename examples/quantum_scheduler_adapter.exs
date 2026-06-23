# Quantum scheduler adapter example (requires :quantum in mix.exs)
# Run: mix run examples/quantum_scheduler_adapter.exs

IO.puts("""
Configure before use:

  config :kathikon,
    scheduler: Kathikon.Scheduler.Quantum,
    quantum_scheduler: MyApp.KathikonScheduler

Without Quantum loaded, schedule_recurring returns:
  {:error, :quantum_not_available}
""")

IO.inspect(Kathikon.Scheduler.Quantum.schedule_recurring(MyWorker, %{}, cron: "0 * * * *"))

defmodule MyWorker do
  use Kathikon.Worker
  def perform(_), do: :ok
end
