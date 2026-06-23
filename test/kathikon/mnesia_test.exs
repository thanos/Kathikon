defmodule Kathikon.ConfigTest do
  use ExUnit.Case, async: true

  alias Kathikon.Config

  test "reads queue configuration" do
    assert :default in Config.queue_names()
    assert Config.concurrency(:default) == 10
    assert is_integer(Config.poll_interval())
    assert is_integer(Config.scheduler_interval())
    assert is_integer(Config.prune_interval())
    assert is_integer(Config.retention_period())
    assert is_integer(Config.max_attempts())
  end

  test "falls back for unknown queues" do
    assert Config.queue_config(:unknown) == [concurrency: 10]
    assert Config.concurrency(:unknown) == 10
  end

  test "mnesia_copies respects explicit config" do
    Application.put_env(:kathikon, :mnesia_copies, :disc)
    assert Config.mnesia_copies() == :disc

    on_exit(fn -> Application.delete_env(:kathikon, :mnesia_copies) end)
  end

  test "auto uses ram on nonode@nohost" do
    if node() == :nonode@nohost do
      Application.put_env(:kathikon, :mnesia_copies, :auto)
      assert Config.mnesia_copies() == :ram
      on_exit(fn -> Application.delete_env(:kathikon, :mnesia_copies) end)
    end
  end

  test "raises on invalid mnesia_copies" do
    Application.put_env(:kathikon, :mnesia_copies, :bogus)

    assert_raise ArgumentError, ~r/invalid :mnesia_copies/, fn ->
      Config.mnesia_copies()
    end

    on_exit(fn -> Application.delete_env(:kathikon, :mnesia_copies) end)
  end
end

defmodule Kathikon.Storage.Mnesia.SetupTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Job, Storage}
  alias Kathikon.Storage.Mnesia

  setup do
    :ok = Storage.setup()
    Storage.clear_jobs!()
    :ok
  end

  test "setup is idempotent" do
    assert :ok = Mnesia.setup()
    assert :ok = Mnesia.setup()
  end

  test "setup starts mnesia when it is not running" do
    if :mnesia.system_info(:is_running) == :yes do
      :mnesia.stop()
      on_exit(fn -> :mnesia.start() end)
    end

    assert :ok = Mnesia.setup()
    assert :yes = :mnesia.system_info(:is_running)
  end

  test "clear_jobs! removes stored jobs" do
    job =
      Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
      |> Map.put(:state, :available)

    {:ok, _} = Storage.insert(job)
    assert [_] = Storage.all()

    assert :ok = Mnesia.clear_jobs!()
    assert [] = Storage.all()
  end

  test "reset! recreates tables and clears jobs" do
    job =
      Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
      |> Map.put(:state, :available)

    {:ok, _} = Storage.insert(job)
    assert :ok = Mnesia.reset!()
    assert [] = Storage.all()
    assert :kathikon_jobs in :mnesia.system_info(:tables)
  end
end
