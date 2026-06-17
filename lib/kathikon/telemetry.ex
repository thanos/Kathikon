defmodule Kathikon.Telemetry do
  @moduledoc """
  Telemetry events emitted by Kathikon.

  All events are prefixed with `[:kathikon, ...]`.

  ## Attach default logger

      Kathikon.Telemetry.attach_default_logger()

  ## Job events

    * `[:kathikon, :job, :insert]` — job enqueued
    * `[:kathikon, :job, :start]` — `perform/1` started
    * `[:kathikon, :job, :stop]` — success (`metadata.result: :ok`)
    * `[:kathikon, :job, :sleep]` — deferred via `{:sleep, seconds}` (not a failure)
    * `[:kathikon, :job, :retry]` — failure with retries remaining
    * `[:kathikon, :job, :discard]` — max attempts exceeded
    * `[:kathikon, :job, :cancel]` — job cancelled
    * `[:kathikon, :job, :prune]` — terminal job deleted

  ## Runtime events

    * `[:kathikon, :scheduler, :tick]` — scheduled jobs promoted
    * `[:kathikon, :dispatcher, :poll]` — job claimed

  See `docs/guides/telemetry-and-observability.md`.
  """

  require Logger

  @prefix [:kathikon]

  @doc false
  def event(suffix, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(@prefix ++ suffix, measurements, metadata)
  end

  @doc """
  Attaches a default logger handler for Kathikon telemetry events.
  """
  @spec attach_default_logger() :: :ok | {:error, :already_exists}
  def attach_default_logger do
    events =
      for suffix <- [
            [:job, :insert],
            [:job, :start],
            [:job, :stop],
            [:job, :sleep],
            [:job, :retry],
            [:job, :discard],
            [:job, :cancel],
            [:job, :prune],
            [:scheduler, :tick],
            [:dispatcher, :poll]
          ] do
        @prefix ++ suffix
      end

    :telemetry.attach_many(
      "kathikon-default-logger",
      events,
      &__MODULE__.log_event/4,
      nil
    )
  end

  @doc false
  def log_event(event, measurements, metadata, _config) do
    event_name = Enum.join(event, ".")
    queue = Map.get(metadata, :queue, "-")
    job_id = Map.get(metadata, :job_id, "-")

    Logger.info(
      "[kathikon] #{event_name} queue=#{queue} job=#{job_id} #{inspect(measurements)} #{inspect(Map.drop(metadata, [:job]))}"
    )
  end
end
