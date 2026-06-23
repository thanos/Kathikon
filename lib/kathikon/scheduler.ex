defmodule Kathikon.Scheduler do
  @moduledoc """
  Scheduling facade for Kathikon.

  Delegates to the configured scheduler adapter (default: `Kathikon.Scheduler.BuiltIn`).

      config :kathikon, scheduler: Kathikon.Scheduler.BuiltIn

  See `docs/scheduling.md`.
  """

  @doc """
  Schedules a one-time job at a datetime, after a duration, or with a cron expression.
  """
  @spec schedule(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def schedule(worker, args, opts \\ []) when is_atom(worker) and is_map(args) do
    if Keyword.has_key?(opts, :cron) do
      adapter().schedule_recurring(worker, args, opts)
    else
      adapter().schedule_once(worker, args, opts)
    end
  end

  @doc """
  Updates a recurring schedule in place (cron, worker, args, queue, and other opts).

  Changing `:cron` resets the last-fired timestamp so the new expression can match
  on the next tick.
  """
  @spec update_schedule(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def update_schedule(schedule_id, opts), do: adapter().update_schedule(schedule_id, opts)

  @doc """
  Fetches a registered recurring schedule by id.
  """
  @spec fetch_schedule(term()) :: {:ok, map()} | {:error, term()}
  def fetch_schedule(schedule_id), do: adapter().fetch_schedule(schedule_id)

  @doc """
  Cancels a registered recurring schedule.
  """
  @spec cancel_schedule(term()) :: :ok | {:error, term()}
  def cancel_schedule(schedule_id), do: adapter().cancel_schedule(schedule_id)

  @doc """
  Lists registered schedules from the active adapter.
  """
  @spec list_schedules(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_schedules(opts \\ []), do: adapter().list_schedules(opts)

  @doc false
  def adapter do
    Application.get_env(:kathikon, :scheduler, Kathikon.Scheduler.BuiltIn)
  end
end
