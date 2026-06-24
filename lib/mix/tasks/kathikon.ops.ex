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

  Remote use requires a **named local node** and matching cookie on both sides:

      elixir --name ops@127.0.0.1 --cookie SECRET -S mix kathikon.ops --node kathikon@127.0.0.1 summary

  Uses `Kathikon.Dashboard` locally or `Kathikon.Dashboard.RPC` on a remote node.
  """

  use Mix.Task

  alias Kathikon.Dashboard
  alias Kathikon.Dashboard.RPC

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

        Mix.shell().error(
          "commands: summary, jobs, show, pause, resume, cancel, retry, rerun, purge, prune"
        )

      [command | rest] ->
        run_command(command, rest, opts)
    end
  end

  defp run_command(command, rest, opts) do
    dispatch_command(command, rest, remote_node(opts), opts)
  end

  defp dispatch_command("summary", _rest, node, _opts) do
    with {:ok, rows} <- rpc(node, :queue_summary, [[]]), do: print_summary(rows)
  end

  defp dispatch_command("jobs", _rest, node, opts) do
    list_opts = list_job_opts(opts)
    validate_pagination!(list_opts)

    with {:ok, page} <- rpc(node, :list_jobs, [list_opts]), do: print_jobs(page)
  end

  defp dispatch_command("show", rest, node, _opts) do
    case rest do
      [job_id | _] when is_binary(job_id) and job_id != "" ->
        with {:ok, detail} <- rpc(node, :fetch_job, [job_id]), do: print_job_detail(detail)

      _ ->
        Mix.raise("usage: mix kathikon.ops show JOB_ID")
    end
  end

  defp dispatch_command("pause", _rest, node, opts),
    do: run_queue_action(node, :pause_queue, opts)

  defp dispatch_command("resume", _rest, node, opts),
    do: run_queue_action(node, :resume_queue, opts)

  defp dispatch_command("cancel", rest, node, opts),
    do: run_job_or_bulk(rest, node, opts, :cancel_job, :cancel_jobs)

  defp dispatch_command("retry", rest, node, opts),
    do: run_job_or_bulk(rest, node, opts, :retry_job, :retry_jobs)

  defp dispatch_command("rerun", rest, node, opts),
    do: run_job_or_bulk(rest, node, opts, :rerun_job, :rerun_jobs)

  defp dispatch_command("purge", _rest, node, opts) do
    with {:ok, result} <- rpc(node, :purge_jobs, [filter_opts(opts)]) do
      IO.puts("Purged #{result.purged} job(s)")
      print_bulk_errors(Map.get(result, :errors, []))
    end
  end

  defp dispatch_command("prune", _rest, node, _opts) do
    rpc(node, :prune_now, []) |> print_result()
  end

  defp dispatch_command(command, _rest, _node, _opts) do
    Mix.raise("unknown command #{inspect(command)}")
  end

  defp run_job_or_bulk([job_id | _], node, _opts, single, _bulk) do
    rpc(node, single, [job_id]) |> print_result()
  end

  defp run_job_or_bulk([], node, opts, _single, bulk) do
    with {:ok, result} <- rpc(node, bulk, [filter_opts(opts)]), do: print_bulk(result)
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
        Dashboard.states_for_tab(String.to_atom(tab))

      true ->
        nil
    end
  end

  defp parse_tab(nil), do: nil

  defp parse_tab(tab) do
    atom = String.to_atom(tab)

    if atom in Dashboard.state_tabs() do
      atom
    else
      Mix.raise(
        "unknown tab #{inspect(tab)} (expected one of #{inspect(Dashboard.state_tabs())})"
      )
    end
  end

  defp validate_pagination!(opts) do
    if limit = Keyword.get(opts, :limit), do: validate_non_negative!(limit, "--limit")
    if offset = Keyword.get(opts, :offset), do: validate_non_negative!(offset, "--offset")
    :ok
  end

  defp validate_non_negative!(value, flag) when value < 0 do
    Mix.raise("#{flag} must be non-negative")
  end

  defp validate_non_negative!(_value, _flag), do: :ok

  defp remote_node(opts) do
    case opts[:node] do
      nil -> nil
      name -> String.to_atom(name)
    end
  end

  defp rpc(node, fun, args) when not is_nil(node) do
    case RPC.call(node, fun, args) do
      {:error, _} = err ->
        Mix.raise("RPC #{inspect(fun)} on #{node} failed: #{inspect(elem(err, 1))}")

      other ->
        other
    end
  end

  defp rpc(nil, fun, args), do: apply(Dashboard, fun, args)

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
    IO.puts("job:")
    IO.puts(inspect(job, pretty: true, limit: :infinity))
    IO.puts("")
    IO.puts("history events: #{length(history)}")
    Enum.each(history, fn event -> IO.puts(inspect(event)) end)
  end

  defp print_result(:ok), do: IO.puts("ok")

  defp print_result({:ok, job}) when is_map(job) do
    IO.puts("ok #{job.id} state=#{job.state}")
  end

  defp print_result({:ok, other}), do: IO.puts(inspect(other))

  defp print_result({:error, reason}), do: Mix.raise(inspect(reason))

  defp print_bulk(%{succeeded: n, errors: errors}) do
    IO.puts("succeeded: #{n}")
    print_bulk_errors(errors)
  end

  defp print_bulk_errors([]), do: :ok

  defp print_bulk_errors(errors) do
    IO.puts("errors:")
    Enum.each(errors, fn {id, reason} -> IO.puts("  #{id}: #{inspect(reason)}") end)
  end

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(%DateTime{} = dt),
    do: dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
