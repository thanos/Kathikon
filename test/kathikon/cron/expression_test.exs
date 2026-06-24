defmodule Kathikon.Cron.ExpressionTest do
  use ExUnit.Case, async: true

  alias Kathikon.Cron.Expression

  test "expand leaves unknown strings unchanged" do
    assert Expression.expand("5 4 * * *") == "5 4 * * *"
    assert Expression.expand("  @Hourly  ") == "0 * * * *"
  end

  test "parse accepts wildcards and fixed values" do
    assert {:ok, {5, 4, :any, :any, :any}} = Expression.parse("5 4 * * *")
    assert {:ok, {0, 0, 1, 1, :any}} = Expression.parse("@yearly")
  end

  test "parse rejects invalid expressions" do
    assert {:error, :invalid_cron} = Expression.parse("* * *")
    assert {:error, :invalid_cron} = Expression.parse("nope * * * *")
    assert {:error, :invalid_cron} = Expression.parse("99 * * * *")
    assert {:error, :invalid_cron} = Expression.parse("* 99 * * *")
    assert {:error, :invalid_cron} = Expression.parse("* * 32 * *")
    assert {:error, :invalid_cron} = Expression.parse("* * * 13 *")
    assert {:error, :invalid_cron} = Expression.parse("* * * * 9")
    refute Expression.valid?("not-valid")
  end

  test "due? returns false for invalid cron" do
    now = ~U[2026-06-22 09:00:00Z]
    refute Expression.due?("bad cron", nil, now)
  end

  test "due? matches weekly sunday and skips repeat within the same minute" do
    sunday = ~U[2026-06-21 00:00:00Z]
    last = ~U[2026-06-21 00:00:30Z]

    assert Expression.due?("@weekly", nil, sunday)
    refute Expression.due?("@weekly", last, sunday)
  end

  test "due? matches when last_fired is from an earlier minute" do
    nine_am = ~U[2026-06-22 09:00:00Z]
    last = ~U[2026-06-22 08:59:30Z]

    assert Expression.due?("0 9 * * *", last, nine_am)
  end

  test "due? matches explicit sunday day-of-week" do
    sunday = ~U[2026-06-21 12:00:00Z]
    assert Expression.due?("0 12 * * 0", nil, sunday)
    refute Expression.due?("0 12 * * 1", nil, sunday)
  end
end
