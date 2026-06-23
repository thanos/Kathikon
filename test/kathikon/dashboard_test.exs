defmodule Kathikon.DashboardTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Dashboard, Job, Storage}

  setup do
    Storage.setup()
    Storage.clear_jobs!()
    Kathikon.resume_queue(:default)
    :ok
  end

  test "states_for_tab matches lifecycle" do
    assert Dashboard.states_for_tab(:executing) == [:claimed, :running, :waiting_for_children]
    assert Dashboard.states_for_tab(:dead) == [:failed, :dead]
    assert :waiting_for_children not in Dashboard.states_for_tab(:discarded)
  end

  test "actions_for_state reflects v0.2 rules" do
    assert :cancel in Dashboard.actions_for_state(:available)
    assert :cancel not in Dashboard.actions_for_state(:running)
    assert :rerun in Dashboard.actions_for_state(:dead)
    assert Dashboard.actions_for_state(:waiting_for_children) == []
  end

  test "queue_summary ui_counts aggregate scheduled into available" do
    future = DateTime.add(DateTime.utc_now(), 3600, :second)

    {:ok, _scheduled} =
      Kathikon.insert(Kathikon.Workers.SuccessWorker, %{},
        queue: :default,
        schedule_at: future
      )

    assert {:ok, [row | _]} = Dashboard.queue_summary()
    assert row.ui_counts.available >= 1
    assert Map.get(row.counts, :scheduled, 0) >= 1
  end

  test "queue_summary includes completed jobs" do
    {:ok, job} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
    {:ok, _} = await_completed(job.id)

    assert {:ok, [row | _]} = Dashboard.queue_summary()
    assert row.queue == :default
    assert row.ui_counts.completed >= 1
  end

  test "list_jobs filters by state and paginates" do
    {:ok, completed} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
    {:ok, _} = await_completed(completed.id)

    future = DateTime.add(DateTime.utc_now(), 3600, :second)

    {:ok, scheduled} =
      Kathikon.insert(Kathikon.Workers.SuccessWorker, %{},
        queue: :default,
        schedule_at: future
      )

    assert {:ok, page} =
             Dashboard.list_jobs(queue: :default, states: [:completed], limit: 10, offset: 0)

    assert page.total >= 1
    assert Enum.all?(page.jobs, &(&1.state == :completed))
    refute Enum.any?(page.jobs, &(&1.id == scheduled.id))
  end

  test "list_jobs supports tab filter" do
    future = DateTime.add(DateTime.utc_now(), 3600, :second)

    {:ok, _job} =
      Kathikon.insert(Kathikon.Workers.SuccessWorker, %{},
        queue: :default,
        schedule_at: future
      )

    assert {:ok, page} = Dashboard.list_jobs(tab: :available, queue: :default)
    assert page.total >= 1
    assert Enum.all?(page.jobs, &(&1.state in Dashboard.states_for_tab(:available)))
  end

  test "fetch_job returns map and history" do
    {:ok, job} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
    {:ok, _} = await_completed(job.id)

    assert {:ok, %{job: row, history: history}} = Dashboard.fetch_job(job.id)
    assert row.id == job.id
    assert row.state == :completed
    assert is_list(history)
  end

  test "pause and resume queue" do
    assert :ok = Dashboard.pause_queue(:default)
    assert %{paused: true} = Dashboard.queue_status(:default)
    assert :ok = Dashboard.resume_queue(:default)
    assert %{paused: false} = Dashboard.queue_status(:default)
  end

  test "retry_jobs and purge_jobs" do
    job =
      Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default, max_attempts: 1)
      |> Map.put(:state, :dead)
      |> Map.put(:attempts, 1)

    {:ok, _dead_job} = Storage.insert(job)

    assert {:ok, %{succeeded: 1, errors: []}} = Dashboard.rerun_jobs(queue: :default, states: [:dead])

    {:ok, completed} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
    {:ok, _} = await_completed(completed.id)

    assert {:ok, %{purged: n}} = Dashboard.purge_jobs(queue: :default, states: [:completed])
    assert n >= 1
    assert {:error, :not_found} = Kathikon.fetch(completed.id)
  end

  test "cancel_jobs skips running jobs" do
    {:ok, job} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{}, queue: :default)

    running =
      job
      |> Map.put(:state, :running)
      |> Map.put(:started_at, DateTime.utc_now())

    {:ok, _} = Storage.update(running)

    future = DateTime.add(DateTime.utc_now(), 3600, :second)

    {:ok, pending} =
      Kathikon.insert(Kathikon.Workers.SuccessWorker, %{},
        queue: :default,
        schedule_at: future
      )

    assert {:ok, %{succeeded: 1, errors: []}} = Dashboard.cancel_jobs(queue: :default)
    assert {:ok, cancelled} = Kathikon.fetch(pending.id)
    assert cancelled.state == :cancelled
    assert {:ok, still_running} = Kathikon.fetch(job.id)
    assert still_running.state == :running
  end

  defp await_completed(job_id) do
    Kathikon.TestSupport.await_state(job_id, :completed, 10_000)
  end
end

defmodule Kathikon.Dashboard.RPCTest do
  use ExUnit.Case, async: true

  alias Kathikon.Dashboard.RPC

  test "allowed? whitelists dashboard functions" do
    assert RPC.allowed?(:queue_summary)
    refute RPC.allowed?(:purge_now_and_delete_everything)
  end
end
