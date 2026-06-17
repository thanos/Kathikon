defmodule Kathikon.Mnesia.Erlang do
  @moduledoc false

  @behaviour Kathikon.Mnesia.Backend

  @impl true
  def start, do: :mnesia.start()

  @impl true
  def stop, do: :mnesia.stop()

  @impl true
  def system_info(key), do: :mnesia.system_info(key)

  @impl true
  def create_schema(nodes), do: :mnesia.create_schema(nodes)

  @impl true
  def create_table(table, opts), do: :mnesia.create_table(table, opts)

  @impl true
  def wait_for_tables(tables, timeout), do: :mnesia.wait_for_tables(tables, timeout)

  @impl true
  def clear_table(table), do: :mnesia.clear_table(table)

  @impl true
  def delete_table(table), do: :mnesia.delete_table(table)
end
