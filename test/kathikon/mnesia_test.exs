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

defmodule Kathikon.Mnesia.ErlangTest do
  use ExUnit.Case, async: false

  alias Kathikon.Mnesia.Erlang, as: MnesiaBackend

  test "delegates to the mnesia application" do
    assert :yes = MnesiaBackend.system_info(:is_running)
    assert is_list(MnesiaBackend.system_info(:tables))
  end
end

defmodule Kathikon.MnesiaTest do
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  setup do
    Application.put_env(:kathikon, :mnesia_backend, Kathikon.Mnesia.Mock)

    on_exit(fn ->
      Application.put_env(:kathikon, :mnesia_backend, Kathikon.Mnesia.Erlang)
    end)

    :ok
  end

  defp stub_running_tables do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn
      :is_running -> :yes
      :tables -> []
    end)
  end

  test "setup starts mnesia when it is not running" do
    Mox.expect(Kathikon.Mnesia.Mock, :system_info, fn :is_running -> :no end)
    Mox.expect(Kathikon.Mnesia.Mock, :start, fn -> :ok end)
    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ -> :ok end)
    stub_running_tables()

    Mox.expect(Kathikon.Mnesia.Mock, :create_table, 2, fn _, _ -> {:atomic, :ok} end)
    Mox.expect(Kathikon.Mnesia.Mock, :wait_for_tables, fn _, _ -> :ok end)

    assert :ok = Kathikon.Mnesia.setup()
  end

  test "setup restarts mnesia when stopping" do
    Mox.expect(Kathikon.Mnesia.Mock, :system_info, fn :is_running -> :stopping end)
    Mox.expect(Kathikon.Mnesia.Mock, :stop, fn -> :ok end)
    Mox.expect(Kathikon.Mnesia.Mock, :start, fn -> :ok end)
    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ -> {:error, {:already_exists, []}} end)
    stub_running_tables()

    Mox.expect(Kathikon.Mnesia.Mock, :create_table, 2, fn _, _ -> {:atomic, :ok} end)
    Mox.expect(Kathikon.Mnesia.Mock, :wait_for_tables, fn _, _ -> :ok end)

    assert :ok = Kathikon.Mnesia.setup()
  end

  test "setup tolerates existing schema" do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn :is_running -> :yes end)

    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ ->
      {:error, {~c"nonode@nohost", {:already_exists, ~c"nonode@nohost"}}}
    end)

    stub_running_tables()
    Mox.expect(Kathikon.Mnesia.Mock, :create_table, 2, fn _, _ -> {:atomic, :ok} end)
    Mox.expect(Kathikon.Mnesia.Mock, :wait_for_tables, fn _, _ -> :ok end)

    assert :ok = Kathikon.Mnesia.setup()
  end

  test "setup raises when tables time out" do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn :is_running -> :yes end)
    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ -> :ok end)
    stub_running_tables()
    Mox.expect(Kathikon.Mnesia.Mock, :create_table, 2, fn _, _ -> {:atomic, :ok} end)

    Mox.expect(Kathikon.Mnesia.Mock, :wait_for_tables, fn _, _ ->
      {:timeout, [:kathikon_jobs]}
    end)

    assert_raise RuntimeError, ~r/timed out waiting for mnesia tables/, fn ->
      Kathikon.Mnesia.setup()
    end
  end

  test "setup raises on table error" do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn :is_running -> :yes end)
    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ -> :ok end)
    stub_running_tables()
    Mox.expect(Kathikon.Mnesia.Mock, :create_table, 2, fn _, _ -> {:atomic, :ok} end)

    Mox.expect(Kathikon.Mnesia.Mock, :wait_for_tables, fn _, _ ->
      {:error, :broken}
    end)

    assert_raise RuntimeError, ~r/mnesia table error/, fn ->
      Kathikon.Mnesia.setup()
    end
  end

  test "setup raises when table creation fails" do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn :is_running -> :yes end)
    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ -> :ok end)
    stub_running_tables()

    Mox.expect(Kathikon.Mnesia.Mock, :create_table, fn _, _ ->
      {:error, {:badarg, :kathikon_jobs}}
    end)

    assert_raise RuntimeError, ~r/failed to create mnesia table/, fn ->
      Kathikon.Mnesia.setup()
    end
  end

  test "setup skips existing tables" do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn
      :is_running -> :yes
      :tables -> [:kathikon_jobs, :kathikon_queues]
    end)

    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ -> :ok end)
    Mox.expect(Kathikon.Mnesia.Mock, :wait_for_tables, fn _, _ -> :ok end)

    assert :ok = Kathikon.Mnesia.setup()
  end

  test "clear_jobs! skips missing table" do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn :tables -> [] end)
    assert :ok = Kathikon.Mnesia.clear_jobs!()
  end

  test "clear_jobs! clears existing table" do
    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn :tables -> [:kathikon_jobs] end)
    Mox.expect(Kathikon.Mnesia.Mock, :clear_table, fn :kathikon_jobs -> :ok end)
    assert :ok = Kathikon.Mnesia.clear_jobs!()
  end

  test "reset! deletes existing tables and recreates schema" do
    {:ok, agent} = Agent.start_link(fn -> [:kathikon_jobs, :kathikon_queues] end)

    Mox.stub(Kathikon.Mnesia.Mock, :system_info, fn
      :is_running -> :yes
      :tables -> Agent.get(agent, & &1)
    end)

    Mox.expect(Kathikon.Mnesia.Mock, :delete_table, 2, fn table ->
      Agent.update(agent, &List.delete(&1, table))
      :ok
    end)

    Mox.expect(Kathikon.Mnesia.Mock, :create_schema, fn _ -> :ok end)

    Mox.expect(Kathikon.Mnesia.Mock, :create_table, 2, fn table, _opts ->
      Agent.update(agent, &[table | &1])
      {:atomic, :ok}
    end)

    Mox.expect(Kathikon.Mnesia.Mock, :wait_for_tables, fn _, _ -> :ok end)

    assert :ok = Kathikon.Mnesia.reset!()

    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
  end
end
