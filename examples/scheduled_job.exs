# Scheduled job example
# Run: mix run examples/scheduled_job.exs

{:ok, _} = Application.ensure_all_started(:kathikon)

defmodule Example.ScheduledWorker do
  use Kathikon.Worker
  def perform(job), do: IO.inspect(job.args, label: "scheduled fire")
end

at = DateTime.add(DateTime.utc_now(), 5, :second)
{:ok, id} = Kathikon.schedule(Example.ScheduledWorker, %{"source" => "at"}, at: at)
IO.puts("Scheduled job #{id} at #{DateTime.to_iso8601(at)}")
