defmodule Kathikon.DispatcherTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.{Dispatcher, Job}

  @mock Kathikon.Backend.Storage.Mock

  setup :verify_on_exit!

  setup context do
    Kathikon.TestSupport.stub_storage_defaults!()

    queue = :"dispatcher_#{System.unique_integer([:positive])}"

    {:ok, dispatcher} =
      Dispatcher.start_link(
        queue: queue,
        config: [concurrency: 1],
        poll_interval: 60_000,
        storage: @mock
      )

    Mox.allow(@mock, self(), dispatcher)

    on_exit(context, fn ->
      if Process.alive?(dispatcher), do: GenServer.stop(dispatcher)
    end)

    %{dispatcher: dispatcher, queue: queue}
  end

  defp job(worker, attrs, opts) do
    Job.build(worker, attrs, opts)
    |> Map.put(:state, :available)
    |> Map.put(:available_at, DateTime.utc_now())
  end

  defp expect_claim_and_start(work, queue) do
    Mox.expect(@mock, :claim_available_jobs, fn ^queue, 1, _claimant ->
      {:ok, [work]}
    end)

    Mox.expect(@mock, :start_job, fn ^work, _claimant, _now ->
      {:ok, Map.put(work, :state, :running)}
    end)
  end

  test "executes a claimed job successfully", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.SuccessWorker, %{}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :complete_job, fn _id, :ok, _meta ->
      {:ok, %{work | state: :completed, attempts: 1}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "retries failed jobs", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.FailWorker, %{}, queue: queue, max_attempts: 3)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :fail_job, fn id, _reason, _meta ->
      assert id == work.id
      {:ok, %{work | state: :retryable, attempts: 1}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "discards jobs after max attempts", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.FailWorker, %{}, queue: queue, max_attempts: 1)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :fail_job, fn id, _reason, _meta ->
      assert id == work.id
      {:ok, %{work | state: :dead, attempts: 1}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "handles worker exceptions", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.RaiseWorker, %{}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :fail_job, fn _id, {:exception, _, _}, _meta ->
      {:ok, %{work | state: :retryable, errors: [%{reason: "boom"}]}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "defers jobs via {:sleep, seconds}", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.SleepWorker, %{"seconds" => 60}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :update_job, fn id, changes ->
      assert id == work.id
      assert changes.state == :scheduled
      {:ok, Map.merge(work, Map.new(changes))}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "treats invalid {:sleep, seconds} as failure", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.SleepWorker, %{"seconds" => 0}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :fail_job, fn _, {:invalid_sleep, 0}, _ ->
      {:ok, %{work | state: :retryable}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "handles worker throws", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.ThrowWorker, %{}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :fail_job, fn _, {:throw, :thrown}, _ ->
      {:ok, %{work | state: :retryable}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "ignores claim errors", %{dispatcher: dispatcher, queue: queue} do
    Mox.expect(@mock, :claim_available_jobs, fn ^queue, 1, _ -> {:error, :locked} end)
    send(dispatcher, :poll)
    Process.sleep(50)
    assert Process.alive?(dispatcher)
  end

  test "skips polling while queue is paused", %{dispatcher: dispatcher, queue: queue} do
    Kathikon.QueueControl.pause(queue)

    Mox.expect(@mock, :claim_available_jobs, 0, fn _, _, _ ->
      flunk("should not claim while paused")
    end)

    send(dispatcher, :poll)
    Process.sleep(50)
    Kathikon.QueueControl.resume(queue)
  end

  test "stores worker return values", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.ResultWorker, %{}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :complete_job, fn _id, %{value: 42}, _meta ->
      {:ok, %{work | state: :completed, result: %{value: 42}}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "discards jobs when worker returns {:discard, reason}", %{
    dispatcher: dispatcher,
    queue: queue
  } do
    work = job(Kathikon.Workers.DiscardWorker, %{}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :discard_job, fn _id, :not_wanted, _meta ->
      {:ok, %{work | state: :discarded}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "forces retry when worker returns {:retry, reason}", %{
    dispatcher: dispatcher,
    queue: queue
  } do
    work = job(Kathikon.Workers.ForceRetryWorker, %{}, queue: queue)
    expect_claim_and_start(work, queue)

    Mox.expect(@mock, :fail_job, fn _id, :try_again, meta ->
      assert meta[:force_retry]
      {:ok, %{work | state: :retryable}}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end
end
