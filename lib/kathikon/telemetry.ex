defmodule Kathikon.Telemetry do
  @moduledoc """
  Telemetry events emitted by Kathikon.

  All events are prefixed with `[:kathikon, ...]`.

  ## Events

    * `[:kathikon, :job, :insert]` — job enqueued
    * `[:kathikon, :job, :start]` — job execution started
    * `[:kathikon, :job, :stop]` — job execution finished
    * `[:kathikon, :job, :retry]` — job scheduled for retry
    * `[:kathikon, :job, :discard]` — job permanently failed
    * `[:kathikon, :job, :cancel]` — job cancelled
    * `[:kathikon, :job, :prune]` — job pruned from storage
    * `[:kathikon, :scheduler, :tick]` — scheduler promoted jobs
    * `[:kathikon, :dispatcher, :poll]` — dispatcher poll cycle
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
