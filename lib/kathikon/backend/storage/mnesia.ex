defmodule Kathikon.Backend.Storage.Mnesia do
  @moduledoc """
  Deprecated compatibility alias for `Kathikon.Storage.Mnesia`.

  Prefer `Kathikon.Storage.Mnesia` in new code.
  """

  alias Kathikon.Storage.Mnesia

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
end
