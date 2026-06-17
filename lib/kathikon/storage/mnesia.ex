defmodule Kathikon.Storage.Mnesia do
  @moduledoc false

  @behaviour Kathikon.Storage.Backend

  alias Kathikon.Job

  @jobs :kathikon_jobs
  @queues :kathikon_queues

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
