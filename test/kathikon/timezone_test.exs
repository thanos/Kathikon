defmodule Kathikon.TimezoneTest do
  use ExUnit.Case, async: false

  alias Kathikon.Cron.Expression
  alias Kathikon.{Job, Timezone}

  setup context do
    previous = Application.get_env(:kathikon, :timezone)

    if tz = context[:timezone] do
      Application.put_env(:kathikon, :timezone, tz)
    end

    on_exit(fn ->
      if previous,
        do: Application.put_env(:kathikon, :timezone, previous),
        else: Application.delete_env(:kathikon, :timezone)
    end)

    :ok
  end

  describe "configured timezone" do
    test "defaults to UTC" do
      assert Timezone.configured() == "Etc/UTC"
      assert %DateTime{time_zone: "Etc/UTC"} = Timezone.to_local(~U[2026-06-22 12:00:00Z])
    end

    @tag timezone: "America/New_York"
    test "local_now returns configured zone" do
      now = Timezone.local_now()
      assert now.time_zone in ["EDT", "EST", "America/New_York"]
    end

    test "raises for invalid configured timezone on local_now" do
      Application.put_env(:kathikon, :timezone, "Not/A/Timezone")

      assert_raise ArgumentError, ~r/invalid Kathikon timezone "Not\/A\/Timezone"/, fn ->
        Timezone.local_now()
      end
    end

    test "raises for invalid configured timezone on to_local" do
      Application.put_env(:kathikon, :timezone, "Not/A/Timezone")

      assert_raise ArgumentError, ~r/invalid Kathikon timezone "Not\/A\/Timezone"/, fn ->
        Timezone.to_local(~U[2026-06-22 12:00:00Z])
      end
    end
  end

  describe "utc_now/0" do
    test "returns current UTC time" do
      before = DateTime.utc_now()
      assert %DateTime{time_zone: "Etc/UTC"} = utc = Timezone.utc_now()
      after_ = DateTime.utc_now()
      assert DateTime.compare(before, utc) != :gt
      assert DateTime.compare(utc, after_) != :gt
    end
  end

  describe "to_utc/1 and normalize_schedule_at/1" do
    @tag timezone: "America/New_York"
    test "converts naive wall clock to UTC" do
      naive = ~N[2030-06-22 09:00:00]
      assert {:ok, ~U[2030-06-22 13:00:00Z]} = Timezone.to_utc(naive)
    end

    @tag timezone: "America/New_York"
    test "converts zoned DateTime to UTC" do
      {:ok, local} = DateTime.from_naive(~N[2030-06-22 09:00:00], "America/New_York")

      assert {:ok, ~U[2030-06-22 13:00:00Z]} = Timezone.to_utc(local)
      assert {:ok, ~U[2030-06-22 13:00:00Z]} = Timezone.normalize_schedule_at(local)
    end

    @tag timezone: "America/New_York"
    test "resolves ambiguous fall-back times" do
      assert {:ok, %DateTime{time_zone: "Etc/UTC"}} =
               Timezone.to_utc(~N[2026-11-01 01:30:00])
    end

    @tag timezone: "America/New_York"
    test "rejects naive times in DST gap" do
      assert {:error, :ambiguous_local_time} = Timezone.to_utc(~N[2026-03-08 02:30:00])
    end

    test "normalize_schedule_at passes through UTC datetimes" do
      utc = ~U[2030-06-22 13:00:00Z]
      assert {:ok, ^utc} = Timezone.normalize_schedule_at(utc)
    end
  end

  describe "normalize_opts/1" do
    test "returns opts unchanged when schedule_at is absent" do
      assert {:ok, [queue: :email]} = Timezone.normalize_opts(queue: :email)
    end

    @tag timezone: "America/New_York"
    test "normalizes schedule_at in opts" do
      assert {:ok, [schedule_at: ~U[2030-06-22 13:00:00Z]]} =
               Timezone.normalize_opts(schedule_at: ~N[2030-06-22 09:00:00])
    end

    @tag timezone: "America/New_York"
    test "returns error for invalid schedule_at in opts" do
      assert {:error, {:invalid_schedule_at, :ambiguous_local_time}} =
               Timezone.normalize_opts(schedule_at: ~N[2026-03-08 02:30:00])
    end
  end

  describe "scheduling integration" do
    @tag timezone: "America/New_York"
    test "build converts naive schedule_at from configured timezone to UTC" do
      naive = ~N[2030-06-22 09:00:00]

      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{},
          schedule_at: naive,
          queue: :default
        )

      assert job.state == :scheduled
      assert job.scheduled_at == ~U[2030-06-22 13:00:00Z]
    end

    @tag timezone: "America/New_York"
    test "cron matches configured timezone wall clock" do
      nine_am_ny = ~U[2026-06-22 13:00:00Z]
      noon_ny = ~U[2026-06-22 16:00:00Z]

      assert Expression.due?("0 9 * * *", nil, nine_am_ny)
      refute Expression.due?("0 9 * * *", nil, noon_ny)
    end

    @tag timezone: "America/New_York"
    test "@daily fires at local midnight" do
      local_midnight = ~U[2026-06-22 04:00:00Z]
      later = ~U[2026-06-22 05:00:00Z]

      assert Expression.due?("@daily", nil, local_midnight)
      refute Expression.due?("@daily", nil, later)
    end

    @tag timezone: "America/New_York"
    test "insert rejects invalid naive schedule_at in DST gap" do
      assert {:error, {:invalid_schedule_at, :ambiguous_local_time}} =
               Kathikon.insert(Kathikon.Workers.SuccessWorker, %{},
                 schedule_at: ~N[2026-03-08 02:30:00]
               )
    end
  end
end
