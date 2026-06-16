defmodule Kathikon.Storage do
  @moduledoc false

  alias Kathikon.Job

  @jobs :kathikon_jobs
  @queues :kathikon_queues

  @doc """
  Inserts a job into Mnesia.
  """
  @spec insert(Job.t()) :: {:ok, Job.t()} | {:error, term()}
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

  @doc """
  Updates an existing job.
  """
  @spec update(Job.t()) :: {:ok, Job.t()} | {:error, term()}
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

  @doc """
  Fetches a job by id.
  """
  @spec fetch(String.t()) :: {:ok, Job.t()} | {:error, :not_found}
  def fetch(id) do
    :mnesia.transaction(fn ->
      case :mnesia.read(@jobs, id) do
        [{_, _, binary}] -> Job.from_record({:kathikon_jobs, id, binary})
        [] -> :mnesia.abort(:not_found)
      end
    end)
    |> normalize_transaction()
  end

  @doc """
  Atomically claims the highest-priority available job for a queue.
  """
  @spec claim(atom(), DateTime.t()) :: {:ok, Job.t()} | :not_found
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

  @doc """
  Promotes all due scheduled jobs to available in a single transaction.
  """
  @spec promote_scheduled(DateTime.t()) :: non_neg_integer()
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

  @doc """
  Lists jobs scheduled before `now` that should become available.
  """
  @spec scheduled_jobs(DateTime.t()) :: [Job.t()]
  def scheduled_jobs(now) do
    :mnesia.transaction(fn ->
      all_jobs()
      |> Enum.filter(fn job ->
        job.state == :scheduled and DateTime.compare(job.scheduled_at, now) != :gt
      end)
    end)
    |> elem(1)
  end

  @doc """
  Lists jobs eligible for pruning.
  """
  @spec prunable_jobs(DateTime.t()) :: [Job.t()]
  def prunable_jobs(cutoff) do
    :mnesia.transaction(fn ->
      all_jobs()
      |> Enum.filter(fn job ->
        job.state in [:completed, :cancelled, :discarded] and prunable?(job, cutoff)
      end)
    end)
    |> elem(1)
  end

  @doc """
  Deletes a job by id.
  """
  @spec delete(String.t()) :: :ok
  def delete(id) do
    :mnesia.transaction(fn ->
      :mnesia.delete({@jobs, id})
    end)

    :ok
  end

  @doc """
  Lists all jobs. Intended for inspection and tests.
  """
  @spec all() :: [Job.t()]
  def all do
    :mnesia.transaction(fn -> all_jobs() end) |> elem(1)
  end

  @doc """
  Registers queue metadata.
  """
  @spec register_queue(atom(), keyword()) :: :ok
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
