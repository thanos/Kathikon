# Reporting example
# Run: mix run examples/reporting.exs

{:ok, _} = Application.ensure_all_started(:kathikon)

defmodule Example.Worker do
  use Kathikon.Worker
  def perform(_), do: :ok
end

Kathikon.insert(Example.Worker, %{})
Process.sleep(500)

IO.inspect(Kathikon.Report.queue_summary(), label: "queues")
IO.inspect(Kathikon.Report.job_counts(), label: "counts")
IO.inspect(Kathikon.Report.dead_letter_summary(), label: "dead letter")
