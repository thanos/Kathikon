defmodule Kathikon.TestSupport do
  @moduledoc false

  import ExUnit.Assertions

  @order_name Kathikon.TestOrder

  def start_order_agent! do
    case Process.whereis(@order_name) do
      nil -> Agent.start_link(fn -> [] end, name: @order_name)
      _pid -> {:ok, Process.whereis(@order_name)}
    end
  end

  def reset_order! do
    start_order_agent!()
    Agent.update(@order_name, fn _ -> [] end)
  end

  def record_order(label) do
    Agent.update(@order_name, fn list -> list ++ [label] end)
  end

  def order, do: Agent.get(@order_name, & &1)

  def stop_dispatcher(queue) do
    case Registry.lookup(Kathikon.Registry, {:dispatcher, queue}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Kathikon.Queue, pid)
      [] -> :ok
    end
  end

  def reset! do
    Kathikon.Mnesia.clear_jobs!()
    Process.sleep(100)
    Kathikon.Mnesia.clear_jobs!()
    reset_order!()
    :ok
  end

  def await_job(job_id, predicate \\ fn job -> job.state == :completed end, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    do_await(job_id, predicate, deadline)
  end

  defp do_await(job_id, predicate, deadline) do
    case Kathikon.fetch(job_id) do
      {:ok, job} ->
        if predicate.(job) do
          {:ok, job}
        else
          retry_await(job_id, predicate, deadline)
        end

      error ->
        error
    end
  end

  defp retry_await(job_id, predicate, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      Process.sleep(50)
      do_await(job_id, predicate, deadline)
    end
  end

  def await_state(job_id, state, timeout \\ 5_000) do
    await_job(job_id, fn job -> job.state == state end, timeout)
  end

  def await_gone(job_id, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_gone(job_id, deadline)
  end

  defp do_await_gone(job_id, deadline) do
    case Kathikon.fetch(job_id) do
      {:error, :not_found} ->
        :ok

      {:ok, _job} ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk("expected job #{job_id} to be pruned")
        else
          Process.sleep(50)
          do_await_gone(job_id, deadline)
        end

      {:error, _} = error ->
        error
    end
  end
end
