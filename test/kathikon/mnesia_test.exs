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
end

defmodule Kathikon.Backend.Storage.LifecycleTest do
  use ExUnit.Case, async: false

  import Mox

  alias Kathikon.Storage

  @mock Kathikon.Backend.Storage.Mock

  setup :verify_on_exit!

  setup do
    Storage.backend(@mock)

    on_exit(fn ->
      Storage.backend(Kathikon.Backend.Storage.Mnesia)
    end)

    :ok
  end

  test "setup delegates to backend" do
    Mox.expect(@mock, :setup, fn -> :ok end)
    assert :ok = Storage.setup()
  end

  test "clear_jobs! delegates to backend" do
    Mox.expect(@mock, :clear_jobs!, fn -> :ok end)
    assert :ok = Storage.clear_jobs!()
  end

  test "reset! delegates to backend" do
    Mox.expect(@mock, :reset!, fn -> :ok end)
    assert :ok = Storage.reset!()
  end
end

defmodule Kathikon.Backend.Storage.Mnesia.LifecycleTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Backend.Storage.Mnesia, Job, Storage}

  setup do
    Storage.backend(Mnesia)
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
    assert :kathikon_queues in :mnesia.system_info(:tables)
  end
end
