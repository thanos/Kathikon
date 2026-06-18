defmodule Kathikon.TestSupport do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 2]

  @mock Kathikon.Backend.Storage.Mock
  @order_name Kathikon.TestOrder

  @doc """
  Scopes the mock storage backend to the current test process.

  Use for facade tests (`Kathikon.cancel/1`, `Kathikon.fetch/1`, and similar)
  that call `Kathikon.Storage` from the test process. Runtime processes under
  test should receive `storage: #{inspect(@mock)}` at `start_link/1` instead.
  """
  def use_mock_storage!(context) do
    stub_storage_defaults!()
    Kathikon.Storage.set_test_backend!(@mock)

    on_exit(context, fn ->
      Kathikon.Storage.clear_test_backend!()
    end)

    :ok
  end

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

  def stub_storage_defaults! do
    Mox.stub(@mock, :claim, fn _, _ -> :not_found end)

    Mox.stub(@mock, :update, fn job ->
      {:ok, job}
    end)

    Mox.stub(@mock, :insert, fn job ->
      {:ok, job}
    end)

    Mox.stub(@mock, :fetch, fn _ ->
      {:error, :not_found}
    end)

    Mox.stub(@mock, :promote_scheduled, fn _ -> 0 end)
    Mox.stub(@mock, :prunable_jobs, fn _ -> [] end)
    Mox.stub(@mock, :delete, fn _ -> :ok end)
    Mox.stub(@mock, :all, fn -> [] end)
    Mox.stub(@mock, :setup, fn -> :ok end)
    Mox.stub(@mock, :clear_jobs!, fn -> :ok end)
    Mox.stub(@mock, :reset!, fn -> :ok end)
  end

  def reset! do
    Kathikon.Storage.clear_jobs!()
    Process.sleep(100)
    Kathikon.Storage.clear_jobs!()
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
