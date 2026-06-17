defmodule Kathikon.Mnesia do
  @moduledoc """
  Mnesia schema management for Kathikon.

  Mnesia is the active coordination store for jobs, queue metadata, and
  (in later phases) leases, cron schedules, and workflow state.
  """

  @tables [:kathikon_jobs, :kathikon_queues]
  @backend_key :mnesia_backend

  @doc """
  Ensures the Mnesia schema and tables exist on the current node.
  """
  @spec setup() :: :ok
  def setup do
    ensure_schema()
    ensure_tables()
    :ok
  end

  @doc """
  Clears all jobs from storage. Intended for tests.
  """
  @spec clear_jobs!() :: :ok
  def clear_jobs! do
    if table_exists?(:kathikon_jobs) do
      backend().clear_table(:kathikon_jobs)
    end

    :ok
  end

  @doc """
  Drops all Kathikon Mnesia tables and recreates them. Intended for tests.
  """
  @spec reset!() :: :ok
  def reset! do
    delete_existing_tables()
    setup()
    :ok
  end

  @doc false
  def tables, do: @tables

  @doc false
  @spec backend() :: module()
  def backend do
    Application.get_env(:kathikon, @backend_key, Kathikon.Mnesia.Erlang)
  end

  defp delete_existing_tables do
    if mnesia_running?(), do: Enum.each(@tables, &delete_table_if_exists/1)
  end

  defp mnesia_running?, do: backend().system_info(:is_running) == :yes

  defp delete_table_if_exists(table) do
    if table_exists?(table), do: backend().delete_table(table)
  end

  defp ensure_schema do
    case backend().system_info(:is_running) do
      :yes ->
        :ok

      :no ->
        backend().start()

      :stopping ->
        backend().stop()
        backend().start()
    end

    case backend().create_schema([node()]) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
      {:error, {:already_exists, _}} -> :ok
      other -> other
    end
  end

  defp ensure_tables do
    for table <- @tables do
      create_table(table)
    end

    case backend().wait_for_tables(@tables, 5_000) do
      :ok ->
        :ok

      {:timeout, tables} ->
        raise "timed out waiting for mnesia tables: #{inspect(tables)}"

      {:error, reason} ->
        raise "mnesia table error: #{inspect(reason)}"
    end
  end

  defp create_table(:kathikon_jobs) do
    create_if_missing(:kathikon_jobs, table_opts([:id, :payload]))
  end

  defp create_table(:kathikon_queues) do
    create_if_missing(:kathikon_queues, table_opts([:name, :config]))
  end

  defp table_opts(attributes) do
    [
      attributes: attributes,
      type: :ordered_set
    ] ++ storage_opts()
  end

  defp storage_opts do
    if node() == :nonode@nohost do
      [ram_copies: [node()]]
    else
      [disc_copies: [node()]]
    end
  end

  defp create_if_missing(table, opts) do
    if table_exists?(table) do
      :ok
    else
      case backend().create_table(table, opts) do
        {:ok, _} -> :ok
        {:atomic, :ok} -> :ok
        :ok -> :ok
        {:error, {:already_exists, _, _}} -> :ok
        other -> raise "failed to create mnesia table #{table}: #{inspect(other)}"
      end
    end
  end

  defp table_exists?(table) do
    backend().system_info(:tables) |> Enum.member?(table)
  end
end
