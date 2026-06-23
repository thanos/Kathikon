defmodule Kathikon.CronTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Cron, Storage}
  alias Kathikon.Scheduler.BuiltIn
  alias Kathikon.Scheduler.BuiltIn.Tick

  setup do
    Storage.setup()
    Storage.clear_jobs!()
    :ok
  end

  test "insert registers a recurring schedule" do
    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{"n" => 1},
               cron: "0 9 * * *",
               queue: :default
             )

    assert {:ok, schedule} = Cron.fetch(id)
    assert schedule.cron == "0 9 * * *"
    assert schedule.worker == Kathikon.Workers.SuccessWorker
    assert schedule.args == %{"n" => 1}
    assert :ok = Cron.cancel(id)
  end

  test "insert rejects invalid cron" do
    assert {:error, :invalid_cron} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{}, cron: "not-valid")
  end

  test "insert requires cron option" do
    assert {:error, :missing_cron} = Cron.insert(Kathikon.Workers.SuccessWorker, %{})
  end

  test "update changes cron at runtime" do
    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               cron: "0 9 * * *",
               queue: :default
             )

    assert {:ok, updated} = Cron.update(id, cron: "0 10 * * *")
    assert updated.cron == "0 10 * * *"
    assert updated.last_fired_at == nil

    assert {:ok, fetched} = Cron.fetch(id)
    assert fetched.cron == "0 10 * * *"
    assert :ok = Cron.cancel(id)
  end

  test "update rejects invalid cron" do
    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               cron: "0 9 * * *",
               queue: :default
             )

    assert {:error, :invalid_cron} = Cron.update(id, cron: "bad")
    assert :ok = Cron.cancel(id)
  end

  test "update can change worker args and queue" do
    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{"a" => 1},
               cron: "* * * * *",
               queue: :default
             )

    assert {:ok, updated} =
             Cron.update(id,
               args: %{"a" => 2},
               queue: :email,
               worker: Kathikon.Workers.SuccessWorker
             )

    assert updated.args == %{"a" => 2}
    assert updated.queue == :email
    assert :ok = Cron.cancel(id)
  end

  test "fire_due_schedules enqueues jobs when cron matches" do
    now = ~U[2026-06-22 09:00:00Z]

    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               cron: "0 9 * * *",
               queue: :default
             )

    assert BuiltIn.fire_due_schedules(now) == 1

    jobs = Storage.all()
    assert length(jobs) == 1
    assert hd(jobs).worker == Kathikon.Workers.SuccessWorker

    assert {:ok, schedule} = Cron.fetch(id)
    assert schedule.last_fired_at == now
    assert :ok = Cron.cancel(id)
  end

  test "cron does not double-fire within the same minute" do
    now = ~U[2026-06-22 09:00:30Z]

    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               cron: "0 9 * * *",
               queue: :default
             )

    assert BuiltIn.fire_due_schedules(now) == 1
    assert BuiltIn.fire_due_schedules(now) == 0
    assert length(Storage.all()) == 1
    assert :ok = Cron.cancel(id)
  end

  test "list returns registered schedules" do
    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               cron: "0 0 * * *",
               queue: :default
             )

    assert {:ok, schedules} = Cron.list()
    assert Enum.any?(schedules, &(&1.id == id))
    assert :ok = Cron.cancel(id)
  end

  test "valid? checks cron expressions" do
    assert Cron.valid?("* * * * *")
    refute Cron.valid?("not-valid")
  end

  test "preset macros expand and validate" do
    for preset <- ~w(@hourly @daily @midnight @weekly @monthly @yearly @annually) do
      assert Cron.valid?(preset)
    end

    assert Cron.expand("@hourly") == "0 * * * *"
    assert Cron.expand("@daily") == "0 0 * * *"
    assert Cron.expand("@midnight") == "0 0 * * *"
    assert Cron.expand("@weekly") == "0 0 * * 0"
    assert Cron.expand("@monthly") == "0 0 1 * *"
    assert Cron.expand("@yearly") == "0 0 1 1 *"
    assert Cron.expand("@annually") == "0 0 1 1 *"
    assert Cron.valid?("@Daily")
  end

  test "@daily preset fires at midnight UTC" do
    midnight = ~U[2026-06-22 00:00:00Z]
    noon = ~U[2026-06-22 12:00:00Z]

    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               cron: "@daily",
               queue: :default
             )

    assert BuiltIn.fire_due_schedules(midnight) == 1
    assert BuiltIn.fire_due_schedules(noon) == 0
    assert :ok = Cron.cancel(id)
  end

  test "tick process fires due schedules" do
    assert {:ok, id} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               cron: "* * * * *",
               queue: :default
             )

    {:ok, tick} = Tick.start_link(name: false, interval: 50)

    on_exit(fn ->
      if Process.alive?(tick), do: GenServer.stop(tick)
    end)

    Process.sleep(120)
    assert Storage.all() != []
    assert :ok = Cron.cancel(id)
  end

  test "stable id option supports idempotent registration" do
    assert {:ok, "digest"} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               id: "digest",
               cron: "0 9 * * *",
               queue: :default
             )

    assert {:ok, "digest"} =
             Cron.insert(Kathikon.Workers.SuccessWorker, %{},
               id: "digest",
               cron: "0 9 * * *",
               queue: :default
             )

    assert {:ok, schedules} = Cron.list()
    assert Enum.count(schedules, &(&1.id == "digest")) == 1
    assert :ok = Cron.cancel("digest")
  end
end
