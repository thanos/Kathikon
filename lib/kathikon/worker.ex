defmodule Kathikon.Worker do
  @moduledoc """
  Behaviour for Kathikon job workers.

  ## Return values

    * `:ok` — success; result stored per `result: :store | :discard`
    * `{:ok, result}` — success with explicit result
    * `{:error, reason}` — failure; retry with backoff until max attempts, then dead-letter
    * `{:discard, reason}` — permanent discard (no retry)
    * `{:retry, reason}` — failure treated as retryable even when attempts remain
    * `{:sleep, seconds}` — defer without counting as failure

  See `docs/guides/workers.md`.
  """

  @callback perform(job :: Kathikon.Job.t()) ::
              :ok
              | {:ok, term()}
              | {:error, term()}
              | {:discard, term()}
              | {:retry, term()}
              | {:sleep, pos_integer()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Kathikon.Worker
    end
  end
end
