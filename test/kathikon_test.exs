defmodule Kathikon.JobTest do
  use ExUnit.Case, async: true

  alias Kathikon.Job

  test "build creates an immediately available job by default" do
    job = Job.build(Kathikon.Workers.SuccessWorker, %{"x" => 1}, [])

    assert job.state == :available
    assert job.queue == :default
    assert job.priority == 0
    assert job.args == %{"x" => 1}
    assert is_binary(job.id)
  end

  test "build respects schedule_in" do
    job = Job.build(Kathikon.Workers.SuccessWorker, %{}, schedule_in: 60)

    assert job.state == :scheduled
    assert DateTime.diff(job.scheduled_at, job.inserted_at, :second) == 60
  end

  test "build respects schedule_at in the future" do
    at = DateTime.add(DateTime.utc_now(), 120, :second)
    job = Job.build(Kathikon.Workers.SuccessWorker, %{}, schedule_at: at)

    assert job.state == :scheduled
    assert job.scheduled_at == at
  end

  test "backoff grows with attempts" do
    assert Job.backoff_seconds(1) == 5
    assert Job.backoff_seconds(2) == 20
    assert Job.backoff_seconds(3) == 45
  end

  test "claim prefers higher priority jobs" do
    now = DateTime.utc_now()

    low =
      Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, priority: 1)
      |> Map.put(:state, :available)
      |> Map.put(:available_at, now)

    high =
      Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, priority: 10)
      |> Map.put(:state, :available)
      |> Map.put(:available_at, now)

    {:ok, _} = Kathikon.Storage.insert(low)
    {:ok, _} = Kathikon.Storage.insert(high)

    assert {:ok, claimed} = Kathikon.Storage.claim(:default, now)
    assert claimed.priority == 10
  end
end

defmodule Kathikon.IntegrationTest do
  use ExUnit.Case, async: false

  alias Kathikon.TestSupport

  setup do
    TestSupport.reset!()
    :ok
  end

  test "insert executes a successful job" do
    {:ok, job} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{})

    assert {:ok, completed} = TestSupport.await_state(job.id, :completed)
    assert completed.attempts == 1
  end

  test "insert retries failed jobs" do
    {:ok, job} = Kathikon.insert(Kathikon.Workers.CountingWorker, %{})

    assert {:ok, completed} = TestSupport.await_state(job.id, :completed, 10_000)
    assert completed.attempts == 2
    assert length(completed.errors) == 1
  end

  test "insert discards after max attempts" do
    {:ok, job} =
      Kathikon.insert(Kathikon.Workers.FailWorker, %{}, max_attempts: 2)

    assert {:ok, discarded} = TestSupport.await_state(job.id, :discarded, 10_000)
    assert discarded.attempts == 2
  end

  test "cancel removes a pending job from execution" do
    future = DateTime.add(DateTime.utc_now(), 3600, :second)

    {:ok, job} =
      Kathikon.insert(Kathikon.Workers.SuccessWorker, %{}, schedule_at: future)

    assert {:ok, cancelled} = Kathikon.cancel(job.id)
    assert cancelled.state == :cancelled
  end

  test "higher priority jobs run first" do
    TestSupport.reset_order!()
    TestSupport.stop_dispatcher(:priority)
    at = DateTime.add(DateTime.utc_now(), 2, :second)

    {:ok, low} =
      Kathikon.insert(Kathikon.Workers.PriorityWorker, %{"label" => "low"},
        queue: :priority,
        schedule_at: at,
        priority: 1
      )

    {:ok, high} =
      Kathikon.insert(Kathikon.Workers.PriorityWorker, %{"label" => "high"},
        queue: :priority,
        schedule_at: at,
        priority: 10
      )

    [{pid, _}] = Registry.lookup(Kathikon.Registry, {:dispatcher, :priority})
    assert :sys.get_state(pid).concurrency == 1

    assert {:ok, _} = TestSupport.await_state(low.id, :completed, 10_000)
    assert {:ok, _} = TestSupport.await_state(high.id, :completed, 10_000)

    assert TestSupport.order() == ["high", "low"]
  end

  test "scheduler promotes scheduled jobs" do
    {:ok, job} =
      Kathikon.insert(Kathikon.Workers.SuccessWorker, %{}, schedule_in: 1)

    assert job.state == :scheduled
    assert {:ok, completed} = TestSupport.await_state(job.id, :completed, 10_000)
    assert completed.state == :completed
  end

  test "pruner removes old terminal jobs" do
    {:ok, job} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{})
    assert {:ok, _} = TestSupport.await_state(job.id, :completed)

    Application.put_env(:kathikon, :retention_period, 0)
    send(Kathikon.Pruner, :tick)
    assert TestSupport.await_gone(job.id)
  end
end
