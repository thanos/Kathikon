defmodule Kathikon.DispatcherTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.{Dispatcher, Job, Storage}

  setup :verify_on_exit!

  setup do
    Kathikon.TestSupport.stub_storage_defaults!()
    Storage.backend(Kathikon.Storage.Mock)

    on_exit(fn ->
      Storage.backend(Kathikon.Storage.Mnesia)
    end)

    queue = :"dispatcher_#{System.unique_integer([:positive])}"

    {:ok, dispatcher} =
      Dispatcher.start_link(queue: queue, config: [concurrency: 1], poll_interval: 60_000)

    Mox.allow(Kathikon.Storage.Mock, self(), dispatcher)

    on_exit(fn ->
      if Process.alive?(dispatcher), do: GenServer.stop(dispatcher)
    end)

    %{dispatcher: dispatcher, queue: queue}
  end

  defp job(worker, attrs \\ %{}, opts \\ []) do
    Job.build(worker, attrs, opts)
    |> Map.put(:state, :available)
    |> Map.put(:available_at, DateTime.utc_now())
  end

  test "executes a claimed job successfully", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.SuccessWorker, %{}, queue: queue)

    Mox.expect(Kathikon.Storage.Mock, :claim, fn ^queue, _ -> {:ok, work} end)

    Mox.expect(Kathikon.Storage.Mock, :update, fn updated ->
      assert updated.state == :completed
      assert updated.attempts == 1
      {:ok, updated}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "retries failed jobs", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.FailWorker, %{}, queue: queue, max_attempts: 3)

    Mox.expect(Kathikon.Storage.Mock, :claim, fn ^queue, _ -> {:ok, work} end)

    Mox.expect(Kathikon.Storage.Mock, :update, fn updated ->
      assert updated.state == :retryable
      assert updated.attempts == 1
      {:ok, updated}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "discards jobs after max attempts", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.FailWorker, %{}, queue: queue, max_attempts: 1)

    Mox.expect(Kathikon.Storage.Mock, :claim, fn ^queue, _ -> {:ok, work} end)

    Mox.expect(Kathikon.Storage.Mock, :update, fn updated ->
      assert updated.state == :discarded
      {:ok, updated}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "handles worker exceptions", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.RaiseWorker, %{}, queue: queue)

    Mox.expect(Kathikon.Storage.Mock, :claim, fn ^queue, _ -> {:ok, work} end)

    Mox.expect(Kathikon.Storage.Mock, :update, fn updated ->
      assert updated.state == :retryable
      assert hd(updated.errors).reason =~ "boom"
      {:ok, updated}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "handles worker throws", %{dispatcher: dispatcher, queue: queue} do
    work = job(Kathikon.Workers.ThrowWorker, %{}, queue: queue)

    Mox.expect(Kathikon.Storage.Mock, :claim, fn ^queue, _ -> {:ok, work} end)

    Mox.expect(Kathikon.Storage.Mock, :update, fn updated ->
      assert updated.state == :retryable
      {:ok, updated}
    end)

    send(dispatcher, :poll)
    Process.sleep(100)
  end

  test "ignores claim errors", %{dispatcher: dispatcher, queue: queue} do
    Mox.expect(Kathikon.Storage.Mock, :claim, fn ^queue, _ -> {:error, :locked} end)
    send(dispatcher, :poll)
    Process.sleep(50)
    assert Process.alive?(dispatcher)
  end
end
