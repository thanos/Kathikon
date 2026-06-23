defmodule Kathikon.Job.StateMachineTest do
  use ExUnit.Case, async: true

  alias Kathikon.Job.StateMachine

  test "allows valid transitions" do
    assert :ok = StateMachine.transition(:available, :claimed)
    assert :ok = StateMachine.transition(:claimed, :running)
    assert :ok = StateMachine.transition(:running, :completed)
    assert :ok = StateMachine.transition(:running, :retryable)
    assert :ok = StateMachine.transition(:failed, :dead)
  end

  test "rejects invalid transitions" do
    assert {:error, {:invalid_transition, :completed, :running}} =
             StateMachine.transition(:completed, :running)

    assert {:error, {:invalid_transition, :dead, :available}} =
             StateMachine.transition(:dead, :available)
  end

  test "terminal states have no outbound transitions" do
    assert StateMachine.terminal?(:completed)
    assert StateMachine.terminal?(:dead)
    assert StateMachine.reachable_from(:completed) == []
  end

  test "normalizes executing to running" do
    assert StateMachine.allowed?(:executing, :completed)
  end
end
