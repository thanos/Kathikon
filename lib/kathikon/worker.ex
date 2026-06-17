defmodule Kathikon.Worker do
  @moduledoc """
  Behaviour for Kathikon job workers.

  Workers implement `perform/1` and are invoked by the dispatcher when a job
  is claimed. Return `:ok` on success, `{:error, reason}` to trigger a retry,
  or `{:sleep, seconds}` to defer the job without recording a failure.

  ## Example

      defmodule MyApp.SendEmailWorker do
        use Kathikon.Worker

        @impl true
        def perform(%Kathikon.Job{args: %{"user_id" => user_id}}) do
          MyApp.Mailer.send(user_id)
          :ok
        end
      end

      {:ok, _job} = Kathikon.insert(MyApp.SendEmailWorker, %{"user_id" => "42"})

  ## Error handling

      def perform(%{args: %{"url" => url}}) do
        case MyApp.HTTP.get(url) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end

  Uncaught exceptions are converted to `{:error, {:exception, ...}}` and retried.

  ## Deferring without failure

      def perform(%{args: %{"retry_after" => seconds}}) do
        {:sleep, seconds}
      end

  The job moves to `:scheduled` and runs again after the delay. Unlike
  `{:error, reason}`, this does not increment `attempts` or append to `errors`.

  See `docs/guides/workers.md`.
  """

  @callback perform(job :: Kathikon.Job.t()) ::
              :ok | {:error, term()} | {:sleep, pos_integer()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Kathikon.Worker
    end
  end
end
