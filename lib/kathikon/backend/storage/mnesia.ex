defmodule Kathikon.Backend.Storage.Mnesia do
  @moduledoc """
  Deprecated compatibility alias for `Kathikon.Storage.Mnesia`.

  Prefer `Kathikon.Storage.Mnesia` in new code.
  """

  alias Kathikon.Storage.Mnesia

  @doc false
  defdelegate setup(), to: Mnesia
  @doc false
  defdelegate clear_jobs!(), to: Mnesia
  @doc false
  defdelegate reset!(), to: Mnesia
  @doc false
  defdelegate insert(job), to: Mnesia
  @doc false
  defdelegate update(job), to: Mnesia
  @doc false
  defdelegate fetch(id), to: Mnesia
  @doc false
  defdelegate claim(queue, now), to: Mnesia
  @doc false
  defdelegate promote_scheduled(now), to: Mnesia
  @doc false
  defdelegate prunable_jobs(cutoff), to: Mnesia
  @doc false
  defdelegate delete(id), to: Mnesia
  @doc false
  defdelegate all(), to: Mnesia
  @doc false
  defdelegate insert_job(job), to: Mnesia
  @doc false
  defdelegate get_job(id), to: Mnesia
  @doc false
  defdelegate update_job(id, changes), to: Mnesia
  @doc false
  defdelegate claim_job(id, claimant), to: Mnesia
  @doc false
  defdelegate claim_available_jobs(queue, limit, claimant), to: Mnesia
  @doc false
  defdelegate claim_and_start_available_jobs(queue, limit, claimant), to: Mnesia
  @doc false
  defdelegate start_job(job, claimant, now \\ DateTime.utc_now()), to: Mnesia
  @doc false
  defdelegate complete_job(id, result, metadata), to: Mnesia
  @doc false
  defdelegate fail_job(id, error, metadata), to: Mnesia
  @doc false
  defdelegate retry_job(id, opts \\ []), to: Mnesia
  @doc false
  defdelegate discard_job(id, reason, metadata), to: Mnesia
  @doc false
  defdelegate cancel_job(id, reason, metadata), to: Mnesia
  @doc false
  defdelegate list_jobs(opts \\ []), to: Mnesia
  @doc false
  defdelegate insert_history_event(job_id, event), to: Mnesia
  @doc false
  defdelegate list_history(job_id), to: Mnesia
  @doc false
  defdelegate move_to_dead_letter(id, reason, metadata), to: Mnesia
  @doc false
  defdelegate list_dead_jobs(opts \\ []), to: Mnesia
  @doc false
  defdelegate defer_job(id, scheduled_at, metadata), to: Mnesia
  @doc false
  defdelegate write_batch(batch), to: Mnesia
  @doc false
  defdelegate fetch_batch(batch_id), to: Mnesia
  @doc false
  defdelegate start_batch(parent_id, child_jobs, batch_attrs), to: Mnesia
  @doc false
  defdelegate record_batch_child_finished(child_job), to: Mnesia
end
