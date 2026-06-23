defmodule Kathikon.BatchTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Batch, Job, Storage}

  setup do
    Storage.setup()
    Storage.clear_jobs!()
    :ok
  end

  test "batch tracks children and enqueues continuation" do
    parent =
      Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
      |> Map.put(:state, :running)

    {:ok, parent} = Storage.insert(parent)

    child_specs = [
      {Kathikon.Workers.SuccessWorker, %{"n" => 1}, [queue: :default]},
      {Kathikon.Workers.SuccessWorker, %{"n" => 2}, [queue: :default]}
    ]

    assert {:ok, batch} =
             Batch.start(parent.id, child_specs,
               on_complete: {Kathikon.Workers.SuccessWorker, %{"done" => true}}
             )

    assert batch.pending_count == 2
    assert {:ok, children} = Batch.children(batch.batch_id)
    assert length(children) == 2

    for child_id <- children do
      claimant = %{
        node: node(),
        pid: "test",
        claimed_at: DateTime.utc_now(),
        dispatcher_id: self()
      }

      {:ok, claimed} = Storage.claim_job(child_id, claimant)
      {:ok, running} = Storage.start_job(claimed, claimant)
      {:ok, _} = Storage.complete_job(running.id, :ok, %{attempt: 1})
      Batch.handle_child_finished(%{running | state: :completed, batch_id: batch.batch_id})
    end

    assert {:ok, status} = Batch.status(batch.batch_id)
    assert status.status == :completed
  end
end
