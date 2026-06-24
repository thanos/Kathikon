defmodule Kathikon.TestSupport do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 2]

  @mock Kathikon.Storage.Mock
  @order_name Kathikon.TestOrder

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

  def resume_all_queues! do
    for queue <- Kathikon.Config.queue_names() do
      Kathikon.resume_queue(queue)
    end

    :ok
  end

  def stub_storage_defaults! do
    Mox.stub(@mock, :claim, fn _, _ -> :not_found end)
    Mox.stub(@mock, :claim_available_jobs, fn _, _, _ -> {:ok, []} end)

    Mox.stub(@mock, :claim_and_start_available_jobs, fn _, _, _ -> {:ok, []} end)

    Mox.stub(@mock, :defer_job, fn id, at, _meta ->
      {:ok, stub_job(id, state: :scheduled, scheduled_at: at, available_at: at)}
    end)

    Mox.stub(@mock, :claim_job, fn _, _ -> {:error, :not_claimable} end)

    Mox.stub(@mock, :start_job, fn job, _claimant, _now ->
      {:ok, Map.put(job, :state, :running)}
    end)

    Mox.stub(@mock, :update, fn job -> {:ok, job} end)

    Mox.stub(@mock, :update_job, fn id, changes ->
      {:ok, stub_job(id, changes)}
    end)

    Mox.stub(@mock, :insert, fn job -> {:ok, job} end)
    Mox.stub(@mock, :insert_job, fn job -> {:ok, job.id} end)
    Mox.stub(@mock, :fetch, fn _ -> {:error, :not_found} end)
    Mox.stub(@mock, :get_job, fn _ -> {:error, :not_found} end)

    Mox.stub(@mock, :complete_job, fn id, _result, _meta ->
      {:ok, stub_job(id, state: :completed)}
    end)

    Mox.stub(@mock, :fail_job, fn id, _error, _meta ->
      {:ok, stub_job(id, state: :retryable)}
    end)

    Mox.stub(@mock, :discard_job, fn id, _, _ -> {:ok, stub_job(id, state: :discarded)} end)
    Mox.stub(@mock, :cancel_job, fn id, _, _ -> {:ok, stub_job(id, state: :cancelled)} end)
    Mox.stub(@mock, :retry_job, fn id, _ -> {:ok, stub_job(id, state: :available)} end)
    Mox.stub(@mock, :move_to_dead_letter, fn id, _, _ -> {:ok, stub_job(id, state: :dead)} end)
    Mox.stub(@mock, :list_jobs, fn _ -> {:ok, []} end)
    Mox.stub(@mock, :list_jobs_page, fn _ -> {:ok, %{jobs: [], total: 0}} end)
    Mox.stub(@mock, :list_dead_jobs, fn _ -> {:ok, []} end)
    Mox.stub(@mock, :insert_history_event, fn _, _ -> :ok end)
    Mox.stub(@mock, :list_history, fn _ -> {:ok, []} end)
    Mox.stub(@mock, :promote_scheduled, fn _ -> 0 end)
    Mox.stub(@mock, :prunable_jobs, fn _ -> [] end)
    Mox.stub(@mock, :delete, fn _ -> :ok end)
    Mox.stub(@mock, :all, fn -> [] end)
    Mox.stub(@mock, :setup, fn -> :ok end)
    Mox.stub(@mock, :clear_jobs!, fn -> :ok end)
    Mox.stub(@mock, :reset!, fn -> :ok end)
  end

  defp stub_job(id, attrs) do
    base = %Kathikon.Job{
      id: id,
      queue: :default,
      worker: MyStubWorker,
      args: %{},
      state: :available
    }

    Map.merge(base, Map.new(attrs))
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

defmodule MyStubWorker do
  use Kathikon.Worker
  def perform(_), do: :ok
end
