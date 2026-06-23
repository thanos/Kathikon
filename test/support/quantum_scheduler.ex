defmodule Kathikon.TestQuantumScheduler do
  @moduledoc false

  @behaviour Kathikon.Scheduler.Quantum.Scheduler

  @table :kathikon_test_quantum

  def reset! do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table)
    end

    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ -> :ok
    end
  end

  @impl true
  def add_job(name, opts) do
    ensure_table!()

    job = %{
      name: name,
      schedule: Keyword.get(opts, :schedule),
      state: :active
    }

    :ets.insert(@table, {name, job})
    {:ok, name}
  end

  @impl true
  def delete_job(name) do
    ensure_table!()
    :ets.delete(@table, name)
    :ok
  end

  @impl true
  def fetch_job(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{_, job}] -> {:ok, job}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def update_job(name, opts) do
    with {:ok, job} <- fetch_job(name) do
      updated = %{job | schedule: Keyword.get(opts, :schedule, job.schedule)}
      :ets.insert(@table, {name, updated})
      {:ok, updated}
    end
  end

  @impl true
  def jobs do
    ensure_table!()

    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_, job} -> job end)
  end
end
