defmodule Kathikon.ApiTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.{Job, Storage}

  setup :verify_on_exit!

  setup context do
    Kathikon.TestSupport.use_mock_storage!(context)
    :ok
  end

  defp sample_job(state \\ :scheduled) do
    Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
    |> Map.put(:state, state)
  end

  test "cancel rejects completed jobs" do
    job = sample_job(:completed)

    Mox.expect(Kathikon.Backend.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    assert {:error, {:invalid_state, :completed}} = Kathikon.cancel("id")
  end

  test "cancel rejects executing jobs" do
    job = sample_job(:executing)

    Mox.expect(Kathikon.Backend.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    assert {:error, :executing} = Kathikon.cancel("id")
  end

  test "cancel rejects discarded jobs" do
    job = sample_job(:discarded)

    Mox.expect(Kathikon.Backend.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    assert {:error, {:invalid_state, :discarded}} = Kathikon.cancel("id")
  end

  test "cancel updates cancellable jobs" do
    job = sample_job(:scheduled)

    Mox.expect(Kathikon.Backend.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    Mox.expect(Kathikon.Backend.Storage.Mock, :update, fn updated ->
      assert updated.state == :cancelled
      assert updated.cancelled_at
      {:ok, updated}
    end)

    assert {:ok, cancelled} = Kathikon.cancel("id")
    assert cancelled.state == :cancelled
  end

  test "cancel updates retryable jobs" do
    job = sample_job(:retryable)

    Mox.expect(Kathikon.Backend.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    Mox.expect(Kathikon.Backend.Storage.Mock, :update, fn updated ->
      assert updated.state == :cancelled
      {:ok, updated}
    end)

    assert {:ok, cancelled} = Kathikon.cancel("id")
    assert cancelled.state == :cancelled
  end

  test "cancel updates available jobs" do
    job = sample_job(:available)

    Mox.expect(Kathikon.Backend.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)

    Mox.expect(Kathikon.Backend.Storage.Mock, :update, fn updated ->
      assert updated.state == :cancelled
      {:ok, updated}
    end)

    assert {:ok, cancelled} = Kathikon.cancel("id")
    assert cancelled.state == :cancelled
  end

  test "fetch and all delegate to storage" do
    job = sample_job()

    Mox.expect(Kathikon.Backend.Storage.Mock, :fetch, fn "id" -> {:ok, job} end)
    Mox.expect(Kathikon.Backend.Storage.Mock, :all, fn -> [job] end)

    assert {:ok, ^job} = Kathikon.fetch("id")
    assert Kathikon.all() == [job]
  end
end

defmodule Kathikon.SchedulerPrunerTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.{Job, Pruner, Scheduler, Storage}

  @mock Kathikon.Backend.Storage.Mock

  setup :verify_on_exit!

  setup context do
    Kathikon.TestSupport.stub_storage_defaults!()

    {:ok, scheduler} =
      Scheduler.start_link(interval: 60_000, storage: @mock, name: false)

    {:ok, pruner} =
      Pruner.start_link(interval: 60_000, storage: @mock, name: false)

    Mox.allow(@mock, self(), scheduler)
    Mox.allow(@mock, self(), pruner)

    on_exit(context, fn ->
      for pid <- [scheduler, pruner] do
        if Process.alive?(pid), do: GenServer.stop(pid)
      end
    end)

    %{scheduler: scheduler, pruner: pruner}
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

  test "scheduler emits telemetry when jobs are promoted", %{scheduler: scheduler} do
    attach_handler([:kathikon, :scheduler, :tick], self())

    Mox.expect(@mock, :promote_scheduled, fn _ -> 2 end)

    send(scheduler, :tick)

    assert_receive {:telemetry, [:kathikon, :scheduler, :tick], %{promoted: 2}, %{}}
  end

  test "scheduler skips telemetry when nothing promoted", %{scheduler: scheduler} do
    Mox.expect(@mock, :promote_scheduled, fn _ -> 0 end)
    send(scheduler, :tick)
    refute_receive {:telemetry, _, _, _}, 50
  end

  test "pruner deletes terminal jobs and emits telemetry", %{pruner: pruner} do
    job = Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)

    attach_handler([:kathikon, :job, :prune], self())

    Mox.expect(@mock, :prunable_jobs, fn _ -> [job] end)
    Mox.expect(@mock, :delete, fn id -> assert id == job.id end)

    send(pruner, :tick)

    assert_receive {:telemetry, [:kathikon, :job, :prune], %{}, %{job_id: id}}
    assert id == job.id
  end

  test "pruner emits tick telemetry when jobs are pruned", %{pruner: pruner} do
    job = Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)

    attach_handler([:kathikon, :pruner, :tick], self())

    Mox.expect(@mock, :prunable_jobs, fn _ -> [job] end)
    Mox.expect(@mock, :delete, fn _ -> :ok end)

    send(pruner, :tick)

    assert_receive {:telemetry, [:kathikon, :pruner, :tick], %{pruned: 1}, %{}}
  end

  test "storage facade delegates lifecycle functions to the configured backend" do
    Mox.expect(@mock, :setup, fn -> :ok end)
    Mox.expect(@mock, :clear_jobs!, fn -> :ok end)
    Mox.expect(@mock, :reset!, fn -> :ok end)

    assert :ok = Storage.with_backend(@mock, fn -> Storage.setup() end)
    assert :ok = Storage.with_backend(@mock, fn -> Storage.clear_jobs!() end)
    assert :ok = Storage.with_backend(@mock, fn -> Storage.reset!() end)
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
