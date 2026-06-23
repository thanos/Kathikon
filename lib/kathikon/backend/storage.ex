defmodule Kathikon.Backend.Storage do
  @moduledoc """
  Deprecated compatibility alias for `Kathikon.Storage`.

  Prefer `Kathikon.Storage` in new code.
  """

  alias Kathikon.Storage.Mnesia

  @doc false
  def start_job(job, claimant, now \\ DateTime.utc_now()),
    do: Mnesia.start_job(job, claimant, now)

  @doc false
  def setup, do: Mnesia.setup()

  @doc false
  def clear_jobs!, do: Mnesia.clear_jobs!()

  @doc false
  def reset!, do: Mnesia.reset!()

  @doc false
  def insert(job), do: Mnesia.insert(job)

  @doc false
  def update(job), do: Mnesia.update(job)

  @doc false
  def fetch(id), do: Mnesia.fetch(id)

  @doc false
  def claim(queue, now), do: Mnesia.claim(queue, now)

  @doc false
  def promote_scheduled(now), do: Mnesia.promote_scheduled(now)

  @doc false
  def prunable_jobs(cutoff), do: Mnesia.prunable_jobs(cutoff)

  @doc false
  def delete(id), do: Mnesia.delete(id)

  @doc false
  def all, do: Mnesia.all()

  @doc false
  def insert_job(job), do: Mnesia.insert_job(job)

  @doc false
  def get_job(id), do: Mnesia.get_job(id)

  @doc false
  def update_job(id, changes), do: Mnesia.update_job(id, changes)

  @doc false
  def claim_job(id, claimant), do: Mnesia.claim_job(id, claimant)

  @doc false
  def claim_available_jobs(queue, limit, claimant),
    do: Mnesia.claim_available_jobs(queue, limit, claimant)

  @doc false
  def complete_job(id, result, metadata), do: Mnesia.complete_job(id, result, metadata)

  @doc false
  def fail_job(id, error, metadata), do: Mnesia.fail_job(id, error, metadata)

  @doc false
  def retry_job(id, opts \\ []), do: Mnesia.retry_job(id, opts)

  @doc false
  def discard_job(id, reason, metadata), do: Mnesia.discard_job(id, reason, metadata)

  @doc false
  def cancel_job(id, reason, metadata), do: Mnesia.cancel_job(id, reason, metadata)

  @doc false
  def list_jobs(opts \\ []), do: Mnesia.list_jobs(opts)

  @doc false
  def insert_history_event(job_id, event), do: Mnesia.insert_history_event(job_id, event)

  @doc false
  def list_history(job_id), do: Mnesia.list_history(job_id)

  @doc false
  def move_to_dead_letter(id, reason, metadata),
    do: Mnesia.move_to_dead_letter(id, reason, metadata)

  @doc false
  def list_dead_jobs(opts \\ []), do: Mnesia.list_dead_jobs(opts)
end
