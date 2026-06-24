defmodule Kathikon.QueueTest do
  use ExUnit.Case, async: false

  alias Kathikon.Queue

  test "start_configured starts dispatchers for configured queues" do
    assert :ok = Queue.start_configured()

    for queue <- Kathikon.Config.queue_names() do
      assert [{_pid, _}] = Registry.lookup(Kathikon.Registry, {:dispatcher, queue})
    end
  end

  test "ensure_started is idempotent for new and existing queues" do
    queue = :"queue_test_#{System.unique_integer([:positive])}"

    assert :ok = Queue.ensure_started(queue)
    assert :ok = Queue.ensure_started(queue)
    assert [{_pid, _}] = Registry.lookup(Kathikon.Registry, {:dispatcher, queue})
  end

  test "ensure_started recovers after dispatcher crash" do
    queue = :"queue_restart_#{System.unique_integer([:positive])}"
    assert :ok = Queue.ensure_started(queue)

    [{pid, _}] = Registry.lookup(Kathikon.Registry, {:dispatcher, queue})
    Process.exit(pid, :kill)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000

    assert :ok = Queue.ensure_started(queue)
    assert [{new_pid, _}] = Registry.lookup(Kathikon.Registry, {:dispatcher, queue})
    assert new_pid != pid
  end
end
