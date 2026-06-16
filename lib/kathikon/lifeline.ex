defmodule Kathikon.Lifeline do
  @moduledoc """
  Recovery for orphaned and stale jobs.

  This module is a placeholder for Phase 2 (Distributed Coordination).
  The lifeline process will detect jobs stuck in `:executing` after lease
  expiry and return them to the `:retryable` state so they can be reclaimed
  by another node.
  """

  @doc """
  Starts the lifeline recovery process. Not yet implemented.
  """
  @spec start_link(keyword()) :: {:error, :not_implemented}
  def start_link(_opts \\ []) do
    {:error, :not_implemented}
  end
end
