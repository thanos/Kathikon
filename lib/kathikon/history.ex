defmodule Kathikon.History do
  @moduledoc false

  @doc false
  def build_event(job_id, event, from_state, to_state, metadata \\ %{}) do
    %{
      id: generate_id(),
      job_id: job_id,
      event: event,
      from_state: from_state,
      to_state: to_state,
      metadata: metadata,
      inserted_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
