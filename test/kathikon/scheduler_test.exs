defmodule Kathikon.SchedulerTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Job, Scheduler, Storage}
  alias Kathikon.Scheduler.Quantum

  setup do
    Storage.setup()
    Storage.clear_jobs!()
    :ok
  end

  test "schedule at datetime creates scheduled job" do
    at = DateTime.add(DateTime.utc_now(), 3600, :second)

    assert {:ok, job_id} =
             Scheduler.schedule(Kathikon.Workers.SuccessWorker, %{}, at: at, queue: :default)

    assert {:ok, job} = Storage.fetch(job_id)
    assert job.state == :scheduled
  end

  test "schedule in duration creates scheduled job" do
    assert {:ok, job_id} =
             Scheduler.schedule(Kathikon.Workers.SuccessWorker, %{}, in: 120, queue: :default)

    assert {:ok, job} = Storage.fetch(job_id)
    assert job.state == :scheduled
  end

  test "recurring cron registration and update" do
    assert {:ok, schedule_id} =
             Scheduler.schedule(Kathikon.Workers.SuccessWorker, %{},
               cron: "* * * * *",
               queue: :default
             )

    assert {:ok, schedules} = Scheduler.list_schedules()
    assert Enum.any?(schedules, &(&1.id == schedule_id))

    assert {:ok, updated} = Scheduler.update_schedule(schedule_id, cron: "0 * * * *")
    assert updated.cron == "0 * * * *"

    assert :ok = Scheduler.cancel_schedule(schedule_id)
  end

  test "quantum adapter errors when scheduler not configured" do
    result = Quantum.schedule_recurring(Kathikon.Workers.MyWorker, %{}, cron: "* * * * *")

    assert result in [
             {:error, :quantum_not_available},
             {:error, :quantum_scheduler_not_configured}
           ]
  end
end
