# Dead-letter retry example
# Run: mix run examples/dead_letter_retry.exs

{:ok, _} = Application.ensure_all_started(:kathikon)

defmodule Example.FailWorker do
  use Kathikon.Worker
  def perform(_), do: {:error, :always_fails}
end

{:ok, job} = Kathikon.insert(Example.FailWorker, %{}, max_attempts: 1)
Process.sleep(2000)

case Kathikon.fetch(job.id) do
  {:ok, %{state: :dead}} ->
    IO.puts("Job moved to dead-letter queue")
    {:ok, rerun} = Kathikon.retry_dead(job.id)
    IO.inspect(rerun.id, label: "rerun job")

  other ->
    IO.inspect(other, label: "job state")
end
