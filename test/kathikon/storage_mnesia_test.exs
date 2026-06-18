defmodule Kathikon.Backend.Storage.MnesiaTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Job, Storage}

  setup do
    Storage.setup()
    Storage.clear_jobs!()
    :ok
  end

  defp available_job(opts \\ []) do
    Job.build(Kathikon.Workers.SuccessWorker, %{}, opts)
    |> Map.put(:state, :available)
    |> Map.put(:available_at, DateTime.utc_now())
  end

  test "insert rejects duplicate ids" do
    job = available_job()

    assert {:ok, _} = Storage.insert(job)
    assert {:error, {:already_exists, id}} = Storage.insert(job)
    assert id == job.id
  end

  test "update returns not_found for missing job" do
    job = available_job()
    assert {:error, {:not_found, _}} = Storage.update(job)
  end

  test "fetch returns not_found for missing job" do
    assert {:error, :not_found} = Storage.fetch("missing")
  end

  test "claim returns not_found when queue is empty" do
    assert :not_found = Storage.claim(:default, DateTime.utc_now())
  end

  test "promote_scheduled promotes due jobs" do
    now = DateTime.utc_now()

    job =
      Job.build(Kathikon.Workers.SuccessWorker, %{}, schedule_in: 0)
      |> then(fn job -> %{job | state: :scheduled, scheduled_at: now} end)

    {:ok, _} = Storage.insert(job)
    assert Storage.promote_scheduled(now) == 1

    assert {:ok, promoted} = Storage.fetch(job.id)
    assert promoted.state == :available
  end

  test "prunable_jobs lists terminal jobs past cutoff" do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, 1, :second)

    job =
      available_job()
      |> Map.put(:state, :completed)
      |> Map.put(:completed_at, now)

    {:ok, _} = Storage.insert(job)
    assert [fetched] = Storage.prunable_jobs(cutoff)
    assert fetched.id == job.id
  end

  test "delete removes a job" do
    job = available_job()
    {:ok, _} = Storage.insert(job)
    :ok = Storage.delete(job.id)
    assert {:error, :not_found} = Storage.fetch(job.id)
  end

  test "claim prefers higher priority jobs" do
    now = DateTime.utc_now()

    low =
      available_job(queue: :default, priority: 1)
      |> Map.put(:available_at, now)

    high =
      available_job(queue: :default, priority: 10)
      |> Map.put(:available_at, now)

    {:ok, _} = Storage.insert(low)
    {:ok, _} = Storage.insert(high)

    assert {:ok, claimed} = Storage.claim(:default, now)
    assert claimed.priority == 10
  end

  test "all returns every stored job" do
    job = available_job()
    {:ok, _} = Storage.insert(job)
    assert Enum.any?(Storage.all(), &(&1.id == job.id))
  end
end
