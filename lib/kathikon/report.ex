defmodule Kathikon.Report do
  @moduledoc """
  Reporting helpers for queue and job observability.

  Initial implementation scans in-memory Mnesia tables — suitable for
  development and moderate job volumes. See performance notes in
  `docs/reporting.md`.
  """

  alias Kathikon.{Config, Job, Storage}

  @doc """
  Summarizes each queue with job counts by state.
  """
  @spec queue_summary(keyword()) :: {:ok, [map()]} | {:error, term()}
  def queue_summary(_opts \\ []) do
    with {:ok, jobs} <- Storage.list_jobs([]) do
      summaries =
        Config.queue_names()
        |> Enum.map(fn queue ->
          queue_jobs = Enum.filter(jobs, &(&1.queue == queue))

          %{
            queue: queue,
            paused: Kathikon.QueueControl.paused?(queue),
            counts: count_by_state(queue_jobs)
          }
        end)

      {:ok, summaries}
    end
  end

  @doc """
  Returns global job counts grouped by state.
  """
  @spec job_counts(keyword()) :: {:ok, map()} | {:error, term()}
  def job_counts(_opts \\ []) do
    with {:ok, jobs} <- Storage.list_jobs([]) do
      {:ok, count_by_state(jobs)}
    end
  end

  @doc """
  Summarizes failures by worker module.
  """
  @spec failure_summary(keyword()) :: {:ok, [map()]} | {:error, term()}
  def failure_summary(_opts \\ []) do
    with {:ok, jobs} <- Storage.list_jobs([]) do
      summary =
        jobs
        |> Enum.filter(&(&1.state in [:failed, :dead, :retryable, :discarded]))
        |> Enum.group_by(& &1.worker)
        |> Enum.map(fn {worker, worker_jobs} ->
          %{
            worker: worker,
            count: length(worker_jobs),
            last_error: List.last(worker_jobs).last_error
          }
        end)
        |> Enum.sort_by(& &1.count, :desc)

      {:ok, summary}
    end
  end

  @doc """
  Summarizes dead-letter queue jobs.
  """
  @spec dead_letter_summary(keyword()) :: {:ok, map()} | {:error, term()}
  def dead_letter_summary(opts \\ []) do
    with {:ok, dead} <- Storage.list_dead_jobs(opts) do
      {:ok, %{count: length(dead), jobs: Enum.map(dead, &Job.to_map/1)}}
    end
  end

  @doc """
  Returns completed job counts per queue (throughput proxy).
  """
  @spec throughput(keyword()) :: {:ok, [map()]} | {:error, term()}
  def throughput(_opts \\ []) do
    with {:ok, jobs} <- Storage.list_jobs([]) do
      result =
        jobs
        |> Enum.filter(&(&1.state == :completed))
        |> Enum.group_by(& &1.queue)
        |> Enum.map(fn {queue, completed} -> %{queue: queue, completed: length(completed)} end)

      {:ok, result}
    end
  end

  @doc """
  Returns average runtime for completed jobs (microseconds).
  """
  @spec latency(keyword()) :: {:ok, map()} | {:error, term()}
  def latency(_opts \\ []) do
    with {:ok, jobs} <- Storage.list_jobs([]) do
      durations =
        jobs
        |> Enum.filter(fn job ->
          (job.state == :completed and job.started_at) && job.completed_at
        end)
        |> Enum.map(fn job ->
          DateTime.diff(job.completed_at, job.started_at, :microsecond)
        end)

      avg =
        case durations do
          [] -> 0
          list -> Enum.sum(list) / length(list)
        end

      {:ok, %{samples: length(durations), average_microseconds: avg}}
    end
  end

  defp count_by_state(jobs) do
    jobs
    |> Enum.group_by(& &1.state)
    |> Enum.map(fn {state, list} -> {state, length(list)} end)
    |> Map.new()
  end
end
