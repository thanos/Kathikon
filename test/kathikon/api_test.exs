defmodule Kathikon.ApiTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.{Job, Storage}

  setup :verify_on_exit!

  setup do
    Kathikon.TestSupport.stub_storage_defaults!()
    Storage.backend(Kathikon.Storage.Mock)
    on_exit(fn -> Storage.backend(Kathikon.Storage.Mnesia) end)
    :ok
  end

  defp sample_job(state \\ :scheduled) do
    Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
    |> Map.put(:state, state)
  end

  test "cancel rejects completed jobs" do
    job = sample_job(:completed)

    Mox.expect(Kathikon.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    assert {:error, {:invalid_state, :completed}} = Kathikon.cancel("id")
  end

  test "cancel rejects executing jobs" do
    job = sample_job(:executing)

    Mox.expect(Kathikon.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    assert {:error, :executing} = Kathikon.cancel("id")
  end

  test "cancel rejects discarded jobs" do
    job = sample_job(:discarded)

    Mox.expect(Kathikon.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    assert {:error, {:invalid_state, :discarded}} = Kathikon.cancel("id")
  end

  test "cancel updates cancellable jobs" do
    job = sample_job(:scheduled)

    Mox.expect(Kathikon.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    Mox.expect(Kathikon.Storage.Mock, :update, fn updated ->
      assert updated.state == :cancelled
      assert updated.cancelled_at
      {:ok, updated}
    end)

    assert {:ok, cancelled} = Kathikon.cancel("id")
    assert cancelled.state == :cancelled
  end

  test "fetch and all delegate to storage" do
    job = sample_job()

    Mox.expect(Kathikon.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)
    Mox.expect(Kathikon.Storage.Mock, :all, fn -> [job] end)

    assert {:ok, ^job} = Kathikon.fetch("id")
    assert Kathikon.all() == [job]
  end
end

defmodule Kathikon.SchedulerPrunerTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.Job

  setup :verify_on_exit!

  setup do
    Kathikon.TestSupport.stub_storage_defaults!()
    Kathikon.Storage.backend(Kathikon.Storage.Mock)
    on_exit(fn -> Kathikon.Storage.backend(Kathikon.Storage.Mnesia) end)

    scheduler = Process.whereis(Kathikon.Scheduler)
    pruner = Process.whereis(Kathikon.Pruner)
    Mox.allow(Kathikon.Storage.Mock, self(), scheduler)
    Mox.allow(Kathikon.Storage.Mock, self(), pruner)

    :ok
  end

  defp attach_handler(event, test_pid) do
    id = "test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      id,
      event,
      fn ev, measurements, metadata, pid ->
        send(pid, {:telemetry, ev, measurements, metadata})
      end,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  test "scheduler emits telemetry when jobs are promoted" do
    attach_handler([:kathikon, :scheduler, :tick], self())

    Mox.expect(Kathikon.Storage.Mock, :promote_scheduled, fn _ -> 2 end)

    send(Kathikon.Scheduler, :tick)

    assert_receive {:telemetry, [:kathikon, :scheduler, :tick], %{promoted: 2}, %{}}
  end

  test "scheduler skips telemetry when nothing promoted" do
    Mox.expect(Kathikon.Storage.Mock, :promote_scheduled, fn _ -> 0 end)
    send(Kathikon.Scheduler, :tick)
    refute_receive {:telemetry, _, _, _}, 50
  end

  test "pruner deletes terminal jobs and emits telemetry" do
    job = Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)

    attach_handler([:kathikon, :job, :prune], self())

    Mox.expect(Kathikon.Storage.Mock, :prunable_jobs, fn _ -> [job] end)
    Mox.expect(Kathikon.Storage.Mock, :delete, fn id -> assert id == job.id end)

    send(Kathikon.Pruner, :tick)

    assert_receive {:telemetry, [:kathikon, :job, :prune], %{}, %{job_id: id}}
    assert id == job.id
  end
end

defmodule Kathikon.StubsTest do
  use ExUnit.Case, async: true

  test "cron insert is not implemented" do
    assert {:error, :not_implemented} = Kathikon.Cron.insert(MyWorker, %{})
  end

  test "lifeline start is not implemented" do
    assert {:error, :not_implemented} = Kathikon.Lifeline.start_link()
  end
end

defmodule MyWorker do
  @behaviour Kathikon.Worker
  def perform(_), do: :ok
end
