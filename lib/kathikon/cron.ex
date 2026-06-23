defmodule Kathikon.Cron do
  @moduledoc """
  Cron-based recurring job scheduling.

  Registers durable recurring schedules that enqueue Kathikon jobs when their
  cron expression matches. Schedules are stored in Mnesia and evaluated by
  `Kathikon.Scheduler.BuiltIn.Tick`.

  Cron fields and presets are interpreted in `config :kathikon, timezone`.

  ## Examples

      # Register a daily job
      {:ok, id} =
        Kathikon.Cron.insert(MyApp.Workers.SendDigest, %{"list" => "all"},
          cron: "0 9 * * *",
          queue: :email
        )

      # Change the schedule at runtime
      {:ok, schedule} = Kathikon.Cron.update(id, cron: "0 10 * * *")

      # Cancel
      :ok = Kathikon.Cron.cancel(id)

  See `Kathikon.Cron.Expression` for supported cron syntax.
  """

  alias Kathikon.Cron.Expression

  @doc """
  Registers a recurring cron schedule.

  ## Options

    * `:cron` — required 5-field cron expression
    * `:queue` — target queue (default `:default`)
    * `:id` — optional stable schedule id for idempotent registration

  Returns `{:ok, schedule_id}` or `{:error, reason}`.

  ## Examples

      {:ok, id} =
        Kathikon.Cron.insert(MyApp.SendDigest, %{"list" => "all"},
          cron: "0 9 * * *",
          queue: :email
        )
  """
  @spec insert(module(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def insert(worker, args, opts \\ []) when is_atom(worker) and is_map(args) do
    case Keyword.fetch(opts, :cron) do
      :error -> {:error, :missing_cron}
      {:ok, cron} -> Kathikon.Scheduler.schedule(worker, args, Keyword.put(opts, :cron, cron))
    end
  end

  @doc """
  Updates a recurring schedule in real time.

  Supported keys: `:cron`, `:worker`, `:args`, `:queue`, and any job insert options.

  Changing `:cron` resets the last-fired timestamp.

  ## Examples

      {:ok, schedule} = Kathikon.Cron.update(schedule_id, cron: "0 10 * * *")
  """
  @spec update(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def update(schedule_id, opts) when is_binary(schedule_id) do
    Kathikon.Scheduler.update_schedule(schedule_id, opts)
  end

  @doc """
  Fetches a recurring schedule by id.

  ## Examples

      {:ok, schedule} = Kathikon.Cron.fetch(schedule_id)
  """
  @spec fetch(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(schedule_id) when is_binary(schedule_id) do
    Kathikon.Scheduler.fetch_schedule(schedule_id)
  end

  @doc """
  Cancels a recurring schedule.

  ## Examples

      :ok = Kathikon.Cron.cancel(schedule_id)
  """
  @spec cancel(String.t()) :: :ok | {:error, term()}
  def cancel(schedule_id) when is_binary(schedule_id) do
    Kathikon.Scheduler.cancel_schedule(schedule_id)
  end

  @doc """
  Lists all registered recurring schedules.

  ## Examples

      {:ok, schedules} = Kathikon.Cron.list()
  """
  @spec list(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list(opts \\ []), do: Kathikon.Scheduler.list_schedules(opts)

  @doc """
  Returns whether a cron expression is valid.

  ## Examples

      Kathikon.Cron.valid?("0 9 * * *")
      #=> true

      Kathikon.Cron.valid?("not a cron")
      #=> false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(expression), do: Expression.valid?(expression)

  @doc """
  Expands preset macros (`@daily`, `@hourly`, etc.) to canonical cron strings.

  ## Examples

      Kathikon.Cron.expand("@daily")
      #=> "0 0 * * *"
  """
  @spec expand(String.t()) :: String.t()
  def expand(expression), do: Expression.expand(expression)
end
