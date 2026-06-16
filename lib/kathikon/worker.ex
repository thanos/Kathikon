defmodule Kathikon.Worker do
  @moduledoc """
  Behaviour for Kathikon job workers.

  Workers implement `perform/1` and are invoked by the dispatcher when a job
  is claimed.

  ## Example

      defmodule MyApp.SendEmailWorker do
        use Kathikon.Worker

        @impl true
        def perform(%Kathikon.Job{args: %{"user_id" => user_id}}) do
          MyApp.Mailer.send(user_id)
          :ok
        end
      end

  Return `:ok` on success. Return `{:error, reason}` to trigger a retry
  (until `max_attempts` is exhausted).
  """

  @callback perform(job :: Kathikon.Job.t()) :: :ok | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Kathikon.Worker
    end
  end
end
