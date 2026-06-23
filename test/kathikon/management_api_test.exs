defmodule Kathikon.ManagementApiTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Job, Storage}

  setup do
    Storage.setup()
    Storage.clear_jobs!()
    :ok
  end

  test "status result and errors" do
    job =
      Job.build(Kathikon.Workers.SuccessWorker, %{"x" => 1}, queue: :default)
      |> Map.put(:state, :completed)
      |> Map.put(:result, %{done: true})
      |> Map.put(:errors, [%{reason: "none"}])

    {:ok, inserted} = Storage.insert(job)

    assert {:ok, status} = Kathikon.status(inserted.id)
    assert status.state == :completed

    assert {:ok, result} = Kathikon.result(inserted.id)
    assert result == %{done: true}

    assert {:ok, errors} = Kathikon.errors(inserted.id)
    assert errors == [%{reason: "none"}]
  end

  test "pause and resume queue" do
    assert :ok = Kathikon.pause_queue(:default)
    assert %{paused: true} = Kathikon.queue_status(:default)
    assert :ok = Kathikon.resume_queue(:default)
    assert %{paused: false} = Kathikon.queue_status(:default)
  end

  test "rerun creates linked job" do
    job = Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, max_attempts: 3)
    {:ok, original} = Storage.insert(job)

    assert {:ok, rerun} = Kathikon.rerun(original.id)
    assert rerun.rerun_of == original.id
    assert rerun.original_job_id == original.id
  end
end
