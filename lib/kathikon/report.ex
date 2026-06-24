defmodule Kathikon.Report do
  @moduledoc """
  Reporting helpers for queue and job observability.

  Initial implementation scans in-memory Mnesia tables — suitable for
  development and moderate job volumes. See performance notes in
  `docs/reporting.md`.

  ## Examples

      {:ok, queues} = Kathikon.Report.queue_summary()
      {:ok, counts} = Kathikon.Report.job_counts()
      {:ok, %{count: n}} = Kathikon.Report.dead_letter_summary()
  """

  alias Kathikon.{Config, Job, Storage}

  @doc """
  Summarizes each configured queue with job counts by state.

  Options are reserved for future filtering and are currently ignored.

  ## Examples

      {:ok, summaries} = Kathikon.Report.queue_summary()

      hd(summaries)
      #=> %{queue: :default, paused: false, counts: %{available: 2, completed: 10}}
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

  ## Examples

      {:ok, counts} = Kathikon.Report.job_counts()
      counts[:completed]
  """
  @spec job_counts(keyword()) :: {:ok, map()} | {:error, term()}
  def job_counts(_opts \\ []) do
    with {:ok, jobs} <- Storage.list_jobs([]) do
      {:ok, count_by_state(jobs)}
    end
  end

  @doc """
  Summarizes failures by worker module.

  ## Examples

      {:ok, summary} = Kathikon.Report.failure_summary()

      hd(summary)
      #=> %{worker: MyApp.FailWorker, count: 3, last_error: "..."}
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

  ## Options

    * `:queue` — filter by queue

  ## Examples

      {:ok, %{count: count, jobs: jobs}} = Kathikon.Report.dead_letter_summary()
  """
  @spec dead_letter_summary(keyword()) :: {:ok, map()} | {:error, term()}
  def dead_letter_summary(opts \\ []) do
    with {:ok, dead} <- Storage.list_dead_jobs(opts) do
      {:ok, %{count: length(dead), jobs: Enum.map(dead, &Job.to_map/1)}}
    end
  end

  @doc """
  Returns completed job counts per queue (throughput proxy).

  ## Examples

      {:ok, throughput} = Kathikon.Report.throughput()
      #=> [%{queue: :default, completed: 42}]
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

  ## Examples

      {:ok, %{samples: n, average_microseconds: avg}} = Kathikon.Report.latency()
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

  @doc """
  Groups jobs by state and returns a count map.

  Used by reporting helpers and available for custom dashboards.
  """
  @spec count_by_state([Job.t()]) :: %{atom() => non_neg_integer()}
  def count_by_state(jobs) do
    jobs
    |> Enum.group_by(& &1.state)
    |> Enum.map(fn {state, list} -> {state, length(list)} end)
    |> Map.new()
  end
end
