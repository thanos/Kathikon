defmodule Kathikon.Scheduler.QuantumTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.Scheduler.Quantum
  alias Kathikon.Scheduler.Quantum.Mock, as: SchedulerMock
  alias Kathikon.Storage

  setup :verify_on_exit!

  setup context do
    previous_scheduler = Application.get_env(:kathikon, :quantum_scheduler)
    previous_available = Application.get_env(:kathikon, :quantum_available)

    Application.put_env(:kathikon, :quantum_available, fn _ -> true end)

    if Map.has_key?(context, :quantum_scheduler) and context[:quantum_scheduler] == :unset do
      Application.delete_env(:kathikon, :quantum_scheduler)
    else
      scheduler = Map.get(context, :quantum_scheduler, SchedulerMock)
      Application.put_env(:kathikon, :quantum_scheduler, scheduler)
    end

    Storage.setup()
    Storage.clear_jobs!()

    on_exit(fn ->
      restore_env(:quantum_scheduler, previous_scheduler)
      restore_env(:quantum_available, previous_available)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:kathikon, key)
  defp restore_env(key, value), do: Application.put_env(:kathikon, key, value)

  test "available? respects test override" do
    Application.put_env(:kathikon, :quantum_available, false)
    refute Quantum.available?()

    Application.put_env(:kathikon, :quantum_available, true)
    assert Quantum.available?()
  end

  test "schedule_once returns quantum_not_available when dependency is absent" do
    Application.put_env(:kathikon, :quantum_available, false)

    assert {:error, :quantum_not_available} =
             Quantum.schedule_once(Kathikon.Workers.SuccessWorker, %{}, in: 10)
  end

  @tag quantum_scheduler: :unset
  test "schedule_once returns not_configured without scheduler module" do
    assert {:error, :quantum_scheduler_not_configured} =
             Quantum.schedule_once(Kathikon.Workers.SuccessWorker, %{}, in: 10)
  end

  @tag quantum_scheduler: Kathikon.Scheduler.Quantum.MissingScheduler
  test "schedule_once returns not_loaded when scheduler module is missing" do
    assert {:error, :quantum_scheduler_not_loaded} =
             Quantum.schedule_once(Kathikon.Workers.SuccessWorker, %{}, in: 10)
  end

  test "schedule_once delegates to built-in scheduler" do
    assert {:ok, job_id} =
             Quantum.schedule_once(Kathikon.Workers.SuccessWorker, %{},
               in: 30,
               queue: :default
             )

    assert {:ok, job} = Storage.fetch(job_id)
    assert job.state == :scheduled
  end

  test "schedule_recurring rejects invalid cron" do
    assert {:error, :invalid_cron} =
             Quantum.schedule_recurring(Kathikon.Workers.SuccessWorker, %{}, cron: "bad")
  end

  test "schedule_recurring registers job with scheduler mock" do
    Mox.expect(SchedulerMock, :add_job, fn name, opts ->
      assert opts[:schedule] == "0 * * * *"
      assert {Quantum, :enqueue, _args} = opts[:task]
      {:ok, name}
    end)

    assert {:ok, name} =
             Quantum.schedule_recurring(Kathikon.Workers.SuccessWorker, %{},
               cron: "0 * * * *",
               name: :digest
             )

    assert name == :digest
  end

  test "schedule_recurring generates job name when omitted" do
    Mox.expect(SchedulerMock, :add_job, fn name, _opts ->
      assert is_binary(name)
      assert String.starts_with?(name, "kathikon_")
      {:ok, name}
    end)

    assert {:ok, name} =
             Quantum.schedule_recurring(Kathikon.Workers.SuccessWorker, %{}, cron: "0 * * * *")

    assert is_binary(name)
  end

  test "schedule_recurring propagates scheduler errors" do
    Mox.expect(SchedulerMock, :add_job, fn _, _ -> {:error, :boom} end)

    assert {:error, :boom} =
             Quantum.schedule_recurring(Kathikon.Workers.SuccessWorker, %{},
               cron: "0 * * * *",
               name: :failing
             )
  end

  test "schedule_recurring accepts non-tuple scheduler responses" do
    Mox.expect(SchedulerMock, :add_job, fn _, _ -> :ok end)

    assert {:ok, :ok} =
             Quantum.schedule_recurring(QuantumTestWorker, %{}, cron: "0 * * * *", name: :raw)
  end

  test "update_schedule requires cron" do
    assert {:error, :missing_cron} = Quantum.update_schedule(:job, [])
  end

  test "update_schedule rejects invalid cron" do
    assert {:error, :invalid_cron} = Quantum.update_schedule(:job, cron: "bad")
  end

  @tag quantum_scheduler: Kathikon.QuantumSchedulerStub
  test "update_schedule returns not_supported without update_job/2" do
    assert {:error, :not_supported} =
             Quantum.update_schedule(:job, cron: "0 1 * * *")
  end

  test "update_schedule updates cron via scheduler mock" do
    Mox.expect(SchedulerMock, :update_job, fn :job, opts ->
      assert opts[:schedule] == "0 2 * * *"

      {:ok, %{name: :job, schedule: opts[:schedule], state: :active}}
    end)

    assert {:ok, %{id: :job, cron: "0 2 * * *", state: :active}} =
             Quantum.update_schedule(:job, cron: "0 2 * * *")
  end

  test "update_schedule propagates scheduler errors" do
    Mox.expect(SchedulerMock, :update_job, fn _, _ -> {:error, :missing} end)
    assert {:error, :missing} = Quantum.update_schedule(:job, cron: "0 2 * * *")
  end

  test "fetch_schedule uses fetch_job when exported" do
    Mox.expect(SchedulerMock, :fetch_job, fn :job ->
      {:ok, %{name: :job, schedule: "0 3 * * *", state: :active}}
    end)

    assert {:ok, %{id: :job, cron: "0 3 * * *"}} = Quantum.fetch_schedule(:job)
  end

  test "fetch_schedule propagates fetch_job errors" do
    Mox.expect(SchedulerMock, :fetch_job, fn _ -> {:error, :not_found} end)
    assert {:error, :not_found} = Quantum.fetch_schedule(:missing)
  end

  @tag quantum_scheduler: Kathikon.QuantumSchedulerStub
  test "fetch_schedule falls back to jobs/0 listing" do
    assert {:ok, %{id: :listed_job, cron: "0 * * * *"}} =
             Quantum.fetch_schedule(:listed_job)

    assert {:error, :not_found} = Quantum.fetch_schedule(:missing)
  end

  test "cancel_schedule deletes via scheduler mock" do
    Mox.expect(SchedulerMock, :delete_job, fn :job -> :ok end)
    assert :ok = Quantum.cancel_schedule(:job)
  end

  test "list_schedules returns scheduler jobs" do
    Mox.expect(SchedulerMock, :jobs, fn ->
      [%{name: :a, schedule: "0 * * * *", state: :active}]
    end)

    assert {:ok, [%{id: :a, schedule: "0 * * * *", state: :active}]} =
             Quantum.list_schedules()
  end

  test "enqueue inserts durable jobs" do
    assert {:ok, job} =
             Quantum.enqueue(Kathikon.Workers.SuccessWorker, %{}, queue: :default)

    assert job.worker == Kathikon.Workers.SuccessWorker
  end
end

defmodule QuantumTestWorker do
  use Kathikon.Worker
  def perform(_), do: :ok
end
