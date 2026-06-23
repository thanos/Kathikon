defmodule Kathikon.Cron.Expression do
  @moduledoc """
  Minimal 5-field cron expression parser and matcher.

  Supports fixed values and `*` wildcards for minute, hour, day-of-month,
  month, and day-of-week (0–6, Sunday = 0). Fields are matched in the
  timezone configured via `config :kathikon, timezone: ...`.

  ## Presets

  Shorthand macros expand to standard cron expressions:

    * `@hourly` — `0 * * * *`
    * `@daily` — `0 0 * * *`
    * `@midnight` — `0 0 * * *`
    * `@weekly` — `0 0 * * 0`
    * `@monthly` — `0 0 1 * *`
    * `@yearly` — `0 0 1 1 *`
    * `@annually` — `0 0 1 1 *`

  Presets are case-insensitive (`@Daily` = `@daily`).
  """

  @type parsed :: {minute :: term(), hour :: term(), dom :: term(), mon :: term(), dow :: term()}

  @presets %{
    "@hourly" => "0 * * * *",
    "@daily" => "0 0 * * *",
    "@midnight" => "0 0 * * *",
    "@weekly" => "0 0 * * 0",
    "@monthly" => "0 0 1 * *",
    "@yearly" => "0 0 1 1 *",
    "@annually" => "0 0 1 1 *"
  }

  @doc """
  Expands preset macros to a canonical 5-field cron string.

  Returns the input unchanged when it is not a known preset.
  """
  @spec expand(String.t()) :: String.t()
  def expand(expression) when is_binary(expression) do
    Map.get(@presets, normalize_key(expression), expression)
  end

  @doc """
  Parses a cron expression.

  Returns `{:ok, parsed}` or `{:error, :invalid_cron}`.
  """
  @spec parse(String.t()) :: {:ok, parsed()} | {:error, :invalid_cron}
  def parse(expression) when is_binary(expression) do
    expression
    |> expand()
    |> parse_fields()
  end

  @doc """
  Returns whether a cron expression is valid.
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(expression) when is_binary(expression) do
    match?({:ok, _}, parse(expression))
  end

  @doc """
  Returns whether a cron expression is due at `now`, given the last fire time.
  """
  @spec due?(String.t(), DateTime.t() | nil, DateTime.t()) :: boolean()
  def due?(cron, last_fired, %DateTime{} = now) do
    case parse(cron) do
      {:ok, parsed} ->
        local_now = Kathikon.Timezone.to_local(now)

        last_minute =
          case last_fired do
            %DateTime{} = dt -> dt |> Kathikon.Timezone.to_local() |> to_minute()
            _ -> nil
          end

        current =
          {local_now.minute, local_now.hour, local_now.day, local_now.month, weekday(local_now)}

        now_minute = to_minute(local_now)

        matches?(current, parsed) and
          (is_nil(last_minute) or DateTime.compare(last_minute, now_minute) == :lt)

      _ ->
        false
    end
  end

  defp normalize_key(expression) do
    expression |> String.trim() |> String.downcase()
  end

  defp parse_fields(expression) do
    parts = String.split(expression, ~r/\s+/, trim: true)

    with true <- length(parts) == 5,
         [minute, hour, dom, mon, dow] <- Enum.map(parts, &parse_field/1),
         true <- valid_field?(minute, 0, 59),
         true <- valid_field?(hour, 0, 23),
         true <- valid_field?(dom, 1, 31),
         true <- valid_field?(mon, 1, 12),
         true <- valid_field?(dow, 0, 6) do
      {:ok, {minute, hour, dom, mon, dow}}
    else
      _ -> {:error, :invalid_cron}
    end
  end

  defp parse_field("*"), do: :any

  defp parse_field(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :invalid
    end
  end

  defp valid_field?(:any, _min, _max), do: true
  defp valid_field?(:invalid, _, _), do: false
  defp valid_field?(value, min, max) when is_integer(value), do: value >= min and value <= max
  defp valid_field?(_, _, _), do: false

  defp matches?({m, h, d, mo, w}, {cm, ch, cd, cmo, cw}) do
    field_match?(m, cm) and field_match?(h, ch) and field_match?(d, cd) and
      field_match?(mo, cmo) and field_match?(w, cw)
  end

  defp field_match?(_, :any), do: true
  defp field_match?(value, value), do: true
  defp field_match?(_, _), do: false

  defp weekday(%DateTime{} = dt) do
    case Date.day_of_week(DateTime.to_date(dt)) do
      7 -> 0
      day -> day
    end
  end

  defp to_minute(%DateTime{} = dt), do: %{dt | second: 0, microsecond: {0, 0}}
end
