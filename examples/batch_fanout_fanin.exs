# Batch fan-out / fan-in example
# Run: mix run examples/batch_fanout_fanin.exs

{:ok, _} = Application.ensure_all_started(:kathikon)

defmodule Example.LargeQueryWorker do
  use Kathikon.Worker

  def perform(_job) do
    refs = Enum.map(1..3, &"ref-#{&1}")
    {:ok, refs}
  end
end

defmodule Example.ProcessResultWorker do
  use Kathikon.Worker

  def perform(%{args: %{"ref" => ref}}) do
    IO.puts("Processing #{ref}")
    :ok
  end
end

defmodule Example.ReportWorker do
  use Kathikon.Worker

  def perform(%{args: args}), do: IO.inspect(args, label: "batch report")
end

parent =
  Kathikon.Job.build(Example.LargeQueryWorker, %{}, queue: :default)
  |> Map.put(:state, :running)

{:ok, parent} = Kathikon.Storage.insert(parent)

child_specs =
  Enum.map(1..3, fn n ->
    {Example.ProcessResultWorker, %{"ref" => "ref-#{n}"}, [queue: :default]}
  end)

{:ok, batch} =
  Kathikon.Batch.start(parent.id, child_specs,
    on_complete: {Example.ReportWorker, %{"parent_id" => parent.id}}
  )

IO.inspect(batch, label: "batch started")
