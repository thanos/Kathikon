defmodule Kathikon.Timezone do
  @moduledoc """
  Timezone helpers for Kathikon scheduling.

  Configure the application timezone with:

      config :kathikon, timezone: "America/New_York"

  Requires a time zone database (tzdata is included as a dependency):

      config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

  ## Behaviour

    * `:schedule_at` and scheduler `:at` accept `DateTime` (any zone) or
      `NaiveDateTime` (interpreted as wall clock in the configured timezone)
    * Cron expressions and presets (`@daily`, etc.) match against local time
    * `:schedule_in` stays relative to UTC instants (duration-based)
    * All persisted timestamps remain UTC
  """

  @utc "Etc/UTC"

  @doc """
  Returns the configured IANA timezone name.
  """
  @spec configured() :: String.t()
  def configured, do: Kathikon.Config.timezone()

  @doc """
  Returns the current UTC instant.
  """
  @spec utc_now() :: DateTime.t()
  def utc_now, do: DateTime.utc_now()

  @doc """
  Returns the current time in the configured timezone.
  """
  @spec local_now() :: DateTime.t()
  def local_now do
    case DateTime.now(configured()) do
      {:ok, dt} -> dt
      {:error, reason} -> raise ArgumentError, invalid_timezone_message(configured(), reason)
    end
  end

  @doc """
  Converts a UTC `DateTime` to the configured timezone.
  """
  @spec to_local(DateTime.t()) :: DateTime.t()
  def to_local(%DateTime{} = utc) do
    case DateTime.shift_zone(utc, configured()) do
      {:ok, local} -> local
      {:error, reason} -> raise ArgumentError, invalid_timezone_message(configured(), reason)
    end
  end

  @doc """
  Converts a wall-clock time in the configured timezone to UTC.

  Accepts `NaiveDateTime` or `DateTime` (shifted to UTC).
  """
  @spec to_utc(NaiveDateTime.t() | DateTime.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def to_utc(%NaiveDateTime{} = naive) do
    case DateTime.from_naive(naive, configured()) do
      {:ok, local} ->
        shift_to_utc(local)

      {:ambiguous, dt, _other} ->
        shift_to_utc(dt)

      {:gap, _start, _ending} ->
        {:error, :ambiguous_local_time}
    end
  end

  def to_utc(%DateTime{} = dt), do: shift_to_utc(dt)

  @doc """
  Normalizes insert/schedule options, converting `:schedule_at` to UTC.
  """
  @spec normalize_opts(keyword()) :: {:ok, keyword()} | {:error, term()}
  def normalize_opts(opts) do
    case Keyword.get(opts, :schedule_at) do
      nil ->
        {:ok, opts}

      at ->
        case normalize_schedule_at(at) do
          {:ok, utc} -> {:ok, Keyword.put(opts, :schedule_at, utc)}
          {:error, reason} -> {:error, {:invalid_schedule_at, reason}}
        end
    end
  end

  @doc """
  Normalizes a schedule target to UTC for storage and comparison.
  """
  @spec normalize_schedule_at(NaiveDateTime.t() | DateTime.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def normalize_schedule_at(%NaiveDateTime{} = naive), do: to_utc(naive)
  def normalize_schedule_at(%DateTime{} = dt), do: shift_to_utc(dt)

  defp shift_to_utc(%DateTime{} = dt) do
    case DateTime.shift_zone(dt, @utc) do
      {:ok, utc} -> {:ok, utc}
      {:error, reason} -> {:error, reason}
    end
  end

  defp invalid_timezone_message(tz, reason) do
    "invalid Kathikon timezone #{inspect(tz)}: #{inspect(reason)}"
  end
end
