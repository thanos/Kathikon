defmodule Kathikon.Dashboard.RPC do
  @moduledoc """
  Remote dashboard calls over Erlang distribution.

  Requires the target node to run Kathikon with a matching cookie.

  ## Examples

      node = :"kathikon@10.0.0.5"

      {:ok, queues} = Kathikon.Dashboard.RPC.call(node, :queue_summary, [[]])
      {:ok, page} = Kathikon.Dashboard.RPC.call(node, :list_jobs, [[queue: :default, limit: 20]])

  Only `Kathikon.Dashboard` functions should be invoked remotely — do not expose
  arbitrary MFA calls from a UI.
  """

  @default_timeout 5_000

  @doc """
  Invokes `Kathikon.Dashboard.fun/arity` on `node` via `:rpc.call/5`.

  Returns `{:ok, result}`, `{:error, :badrpc}`, or `{:error, :nodedown}`.
  """
  @spec call(node(), atom(), [term()], timeout()) ::
          {:ok, term()} | {:error, :badrpc | :nodedown | term()}
  def call(node, fun, args \\ [], timeout \\ @default_timeout)
      when is_atom(fun) and is_list(args) do
    unless allowed?(fun) do
      {:error, {:rpc_not_allowed, fun}}
    else
      case :rpc.call(node, Kathikon.Dashboard, fun, args, timeout) do
        {:badrpc, :nodedown} -> {:error, :nodedown}
        {:badrpc, reason} -> {:error, {:badrpc, reason}}
        result -> {:ok, result}
      end
    end
  end

  @doc "Returns whether `fun/1` may be called remotely."
  @spec allowed?(atom()) :: boolean()
  def allowed?(fun) when is_atom(fun) do
    fun in [
      :queue_summary,
      :list_jobs,
      :fetch_job,
      :state_tabs,
      :states_for_tab,
      :pause_all,
      :resume_all,
      :pause_queue,
      :resume_queue,
      :queue_status,
      :cancel_job,
      :retry_job,
      :rerun_job,
      :discard_job,
      :discard_jobs,
      :cancel_jobs,
      :retry_jobs,
      :rerun_jobs,
      :purge_jobs,
      :promote_now,
      :prune_now,
      :actions_for_state
    ]
  end
end
