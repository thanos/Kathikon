defmodule Mix.Tasks.Kathikon.Ops do
  @shortdoc "Inspect and control Kathikon queues and jobs"

  @moduledoc """
  Operations CLI for Kathikon (inspect queues/jobs and run management commands).

      mix kathikon.ops summary
      mix kathikon.ops jobs --queue default --state completed --limit 20
      mix kathikon.ops show JOB_ID
      mix kathikon.ops pause --all
      mix kathikon.ops resume --queue emails
      mix kathikon.ops cancel JOB_ID
      mix kathikon.ops retry JOB_ID
      mix kathikon.ops rerun JOB_ID
      mix kathikon.ops purge --queue default --state completed
      mix kathikon.ops --node kathikon@host summary

  Uses `Kathikon.Dashboard` locally or `Kathikon.Dashboard.RPC` on a remote node.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv, _} =
      OptionParser.parse(args,
        strict: [
          node: :string,
          queue: :string,
          state: :string,
          tab: :string,
          limit: :integer,
          offset: :integer,
          all: :boolean
        ],
        aliases: [n: :node, q: :queue, s: :state]
      )

    case argv do
      [] ->
        Mix.shell().error("usage: mix kathikon.ops COMMAND [options]")
        Mix.shell().error("commands: summary, jobs, show, pause, resume, cancel, retry, rerun, purge, prune")

      [command | rest] ->
        run_command(command, rest, opts)
    end
  end

  defp run_command(command, rest, opts) do
    node = remote_node(opts)

    case command do
      "summary" ->
        with {:ok, rows} <- rpc(node, :queue_summary, [[]]) do
          print_summary(rows)
        end

      "jobs" ->
        list_opts = list_job_opts(opts)

        with {:ok, page} <- rpc(node, :list_jobs, [list_opts]) do
          print_jobs(page)
        end

      "show" ->
        [job_id | _] = rest

        with {:ok, detail} <- rpc(node, :fetch_job, [job_id]) do
          print_job_detail(detail)
        end

      "pause" ->
        run_queue_action(node, :pause_queue, opts)

      "resume" ->
        run_queue_action(node, :resume_queue, opts)

      "cancel" ->
        case rest do
          [job_id | _] ->
            rpc(node, :cancel_job, [job_id]) |> print_result()

          [] ->
            with {:ok, result} <- rpc(node, :cancel_jobs, [filter_opts(opts)]) do
              print_bulk(result)
            end
        end

      "retry" ->
        case rest do
          [job_id | _] ->
            rpc(node, :retry_job, [job_id]) |> print_result()

          [] ->
            with {:ok, result} <- rpc(node, :retry_jobs, [filter_opts(opts)]) do
              print_bulk(result)
            end
        end

      "rerun" ->
        case rest do
          [job_id | _] ->
            rpc(node, :rerun_job, [job_id]) |> print_result()

          [] ->
            with {:ok, result} <- rpc(node, :rerun_jobs, [filter_opts(opts)]) do
              print_bulk(result)
            end
        end

      "purge" ->
        with {:ok, result} <- rpc(node, :purge_jobs, [filter_opts(opts)]) do
          IO.puts("Purged #{result.purged} job(s)")
        end

      "prune" ->
        rpc(node, :prune_now, []) |> print_result()

      other ->
        Mix.raise("unknown command #{inspect(other)}")
    end
  end

  defp run_queue_action(node, fun, opts) do
    cond do
      opts[:all] ->
        rpc(node, action_all(fun), []) |> print_result()

      queue = opts[:queue] ->
        rpc(node, fun, [parse_queue!(queue)]) |> print_result()

      true ->
        Mix.raise("pass --queue NAME or --all")
    end
  end

  defp action_all(:pause_queue), do: :pause_all
  defp action_all(:resume_queue), do: :resume_all

  defp list_job_opts(opts) do
    []
    |> maybe_put(:queue, parse_queue(opts[:queue]))
    |> maybe_put(:limit, opts[:limit])
    |> maybe_put(:offset, opts[:offset])
    |> maybe_put(:states, parse_states(opts))
    |> maybe_put(:tab, parse_tab(opts[:tab]))
  end

  defp filter_opts(opts) do
    []
    |> maybe_put(:queue, parse_queue(opts[:queue]))
    |> maybe_put(:states, parse_states(opts))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_queue(nil), do: nil
  defp parse_queue(queue), do: parse_queue!(queue)

  defp parse_queue!(queue) when is_binary(queue), do: String.to_atom(queue)

  defp parse_states(opts) do
    cond do
      states = opts[:state] ->
        states
        |> String.split(",", trim: true)
        |> Enum.map(&String.to_atom/1)

      tab = opts[:tab] ->
        Kathikon.Dashboard.states_for_tab(String.to_atom(tab))

      true ->
        nil
    end
  end

  defp parse_tab(nil), do: nil
  defp parse_tab(tab), do: String.to_atom(tab)

  defp remote_node(opts) do
    case opts[:node] do
      nil -> nil
      name -> String.to_atom(name)
    end
  end

  defp rpc(nil, fun, args), do: apply(Kathikon.Dashboard, fun, args)

  defp rpc(node, fun, args) do
    case Kathikon.Dashboard.RPC.call(node, fun, args) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> Mix.raise("RPC #{inspect(fun)} on #{node} failed: #{inspect(reason)}")
    end
  end

  defp print_summary(rows) do
    header =
      :io_lib.format(
        "~-16s ~8s ~8s ~10s ~9s ~9s ~7s ~7s ~6s",
        ["Queue", "Avail", "Exec", "Completed", "Retry", "Cancel", "Failed", "Total", "Pause"]
      )

    IO.puts(header)
    IO.puts(String.duplicate("-", 90))

    for row <- rows do
      u = Map.get(row, :ui_counts, %{})

      IO.puts(
        :io_lib.format(
          "~-16s ~8w ~8w ~10w ~9w ~9w ~7w ~7w ~6s",
          [
            row.queue,
            u[:available] || 0,
            u[:executing] || row.executing,
            u[:completed] || 0,
            u[:retryable] || 0,
            u[:cancelled] || 0,
            u[:failed] || row.failed,
            row.total,
            if(row.paused, do: "yes", else: "no")
          ]
        )
      )
    end
  end

  defp print_jobs(%{jobs: jobs, total: total, limit: limit, offset: offset}) do
    IO.puts("Showing #{length(jobs)} job(s) (offset #{offset}, limit #{limit}) out of #{total}")
    IO.puts("")

    header =
      :io_lib.format(
        "~-34s ~-12s ~-12s ~-28s ~8s ~22s",
        ["ID", "State", "Queue", "Worker", "Attempts", "Timestamp"]
      )

    IO.puts(header)
    IO.puts(String.duplicate("-", 120))

    for job <- jobs do
      IO.puts(
        :io_lib.format(
          "~-34s ~-12w ~-12w ~-28s ~8s ~22s",
          [
            job.id,
            job.state,
            job.queue,
            job.worker,
            job.attempts_label,
            format_timestamp(job.timestamp)
          ]
        )
      )
    end
  end

  defp print_job_detail(%{job: job, history: history}) do
    IO.inspect(job, label: "job", pretty: true)
    IO.puts("")
    IO.puts("history events: #{length(history)}")
    Enum.each(history, &IO.inspect/1)
  end

  defp print_result(:ok), do: IO.puts("ok")

  defp print_result({:ok, job}) when is_map(job) do
    IO.puts("ok #{job.id} state=#{job.state}")
  end

  defp print_result({:ok, other}), do: IO.inspect(other)

  defp print_result({:error, reason}), do: Mix.raise(inspect(reason))

  defp print_bulk(%{succeeded: n, errors: errors}) do
    IO.puts("succeeded: #{n}")

    unless errors == [] do
      IO.puts("errors:")
      Enum.each(errors, fn {id, reason} -> IO.puts("  #{id}: #{inspect(reason)}") end)
    end
  end

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(%DateTime{} = dt),
    do: dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
