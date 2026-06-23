# Basic worker example
# Run: mix run examples/basic_worker.exs

{:ok, _} = Application.ensure_all_started(:kathikon)

defmodule Example.SuccessWorker do
  use Kathikon.Worker
  def perform(_), do: :ok
end

{:ok, job} = Kathikon.insert(Example.SuccessWorker, %{"hello" => "world"})
IO.inspect(Kathikon.status(job.id), label: "status")
