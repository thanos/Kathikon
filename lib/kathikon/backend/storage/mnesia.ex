defmodule Kathikon.Backend.Storage.Mnesia do
  @moduledoc """
  Mnesia implementation of `Kathikon.Backend.Storage`.

  Tables: `:kathikon_jobs`, `:kathikon_queues`. Copy type is controlled by
  `config :kathikon, mnesia_copies:` (`:ram`, `:disc`, or `:auto`).
  """

  @behaviour Kathikon.Backend.Storage

  alias Kathikon.Job

  @tables [:kathikon_jobs, :kathikon_queues]
  @jobs :kathikon_jobs
  @queues :kathikon_queues

  @impl true
  def setup do
    ensure_schema()
    ensure_tables()
    :ok
  end

  @impl true
  def clear_jobs! do
    if table_exists?(:kathikon_jobs) do
      :mnesia.clear_table(:kathikon_jobs)
    end

    :ok
  end

  @impl true
  def reset! do
    delete_existing_tables()
    setup()
    :ok
  end

  @impl true
  def insert(%Job{} = job) do
    :mnesia.transaction(fn ->
      case :mnesia.read(@jobs, job.id) do
        [] ->
          :mnesia.write(Job.to_record(job))
          job

        _ ->
          :mnesia.abort({:already_exists, job.id})
      end
    end)
    |> normalize_transaction()
  end

  @impl true
  def update(%Job{} = job) do
    :mnesia.transaction(fn ->
      case :mnesia.read(@jobs, job.id) do
        [] -> :mnesia.abort({:not_found, job.id})
        [_] -> :mnesia.write(Job.to_record(job))
      end

      job
    end)
    |> normalize_transaction()
  end

  @impl true
  def fetch(id) do
    :mnesia.transaction(fn ->
      case :mnesia.read(@jobs, id) do
        [{_, _, binary}] -> Job.from_record({:kathikon_jobs, id, binary})
        [] -> :mnesia.abort(:not_found)
      end
    end)
    |> normalize_transaction()
  end

  @impl true
  def claim(queue, now) do
    :mnesia.transaction(fn ->
      jobs =
        all_jobs()
        |> Enum.filter(fn job ->
          job.queue == queue and Job.claimable?(job, now)
        end)
        |> sort_claimable()

      case jobs do
        [] ->
          :mnesia.abort(:not_found)

        [job | _] ->
          claimed = %{job | state: :executing, started_at: now}
          :mnesia.write(Job.to_record(claimed))
          claimed
      end
    end)
    |> case do
      {:atomic, job} -> {:ok, job}
      {:aborted, :not_found} -> :not_found
      {:aborted, reason} -> {:error, reason}
    end
  end

  @impl true
  def promote_scheduled(now) do
    :mnesia.transaction(fn ->
      all_jobs()
      |> Enum.filter(fn job ->
        job.state == :scheduled and DateTime.compare(job.scheduled_at, now) != :gt
      end)
      |> Enum.map(fn job ->
        updated = %{job | state: :available, available_at: now}
        :mnesia.write(Job.to_record(updated))
        updated
      end)
      |> length()
    end)
    |> elem(1)
  end

  @impl true
  def scheduled_jobs(now) do
    :mnesia.transaction(fn ->
      all_jobs()
      |> Enum.filter(fn job ->
        job.state == :scheduled and DateTime.compare(job.scheduled_at, now) != :gt
      end)
    end)
    |> elem(1)
  end

  @impl true
  def prunable_jobs(cutoff) do
    :mnesia.transaction(fn ->
      all_jobs()
      |> Enum.filter(fn job ->
        job.state in [:completed, :cancelled, :discarded] and prunable?(job, cutoff)
      end)
    end)
    |> elem(1)
  end

  @impl true
  def delete(id) do
    :mnesia.transaction(fn ->
      :mnesia.delete({@jobs, id})
    end)

    :ok
  end

  @impl true
  def all do
    :mnesia.transaction(fn -> all_jobs() end) |> elem(1)
  end

  @impl true
  def register_queue(name, config) do
    :mnesia.transaction(fn ->
      :mnesia.write({@queues, name, config})
    end)

    :ok
  end

  defp delete_existing_tables do
    if mnesia_running?(), do: Enum.each(@tables, &delete_table_if_exists/1)
  end

  defp mnesia_running?, do: :mnesia.system_info(:is_running) == :yes

  defp delete_table_if_exists(table) do
    if table_exists?(table), do: :mnesia.delete_table(table)
  end

  defp ensure_schema do
    case :mnesia.system_info(:is_running) do
      :yes ->
        :ok

      :no ->
        :mnesia.start()

      :stopping ->
        :mnesia.stop()
        :mnesia.start()
    end

    case :mnesia.create_schema([node()]) do
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

    case :mnesia.wait_for_tables(@tables, 5_000) do
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
    case Kathikon.Config.mnesia_copies() do
      :ram -> [ram_copies: [node()]]
      :disc -> [disc_copies: [node()]]
    end
  end

  defp create_if_missing(table, opts) do
    if table_exists?(table) do
      :ok
    else
      case :mnesia.create_table(table, opts) do
        {:ok, _} -> :ok
        {:atomic, :ok} -> :ok
        :ok -> :ok
        {:error, {:already_exists, _, _}} -> :ok
        other -> raise "failed to create mnesia table #{table}: #{inspect(other)}"
      end
    end
  end

  defp table_exists?(table) do
    :mnesia.system_info(:tables) |> Enum.member?(table)
  end

  defp all_jobs do
    :mnesia.select(@jobs, [{{:"$1", :_, :"$2"}, [], [:"$2"]}])
    |> Enum.map(&decode_job/1)
  end

  defp decode_job(binary) when is_binary(binary) do
    :erlang.binary_to_term(binary)
  end

  defp sort_claimable(jobs) do
    Enum.sort_by(jobs, fn job ->
      {-job.priority, DateTime.to_unix(job.available_at, :microsecond)}
    end)
  end

  defp prunable?(job, cutoff) do
    timestamp =
      job.completed_at || job.cancelled_at || job.inserted_at

    timestamp && DateTime.compare(timestamp, cutoff) != :gt
  end

  defp normalize_transaction({:atomic, result}), do: {:ok, result}
  defp normalize_transaction({:aborted, reason}), do: {:error, reason}
end
