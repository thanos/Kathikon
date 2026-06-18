defmodule Kathikon.Queue do
  @moduledoc """
  Queue registration and dispatcher lifecycle.

  A `DynamicSupervisor` that starts one `Kathikon.Dispatcher` per queue.
  `start_configured/0` runs at application boot; `ensure_started/1` is
  called on each `Kathikon.insert/3`.

  ## Example

      :ok = Kathikon.Queue.ensure_started(:emails)

  See `docs/guides/queues-and-concurrency.md`.
  """

  use DynamicSupervisor

  alias Kathikon.{Config, Dispatcher}

  @name __MODULE__

  @doc false
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: @name)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Ensures a dispatcher is running for the given queue.
  """
  @spec ensure_started(atom()) :: :ok
  def ensure_started(queue) when is_atom(queue) do
    config = Config.queue_config(queue)

    case DynamicSupervisor.start_child(@name, {Dispatcher, queue: queue, config: config}) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, {:already_present, _pid}} -> :ok
      other -> other
    end
  end

  @doc """
  Starts dispatchers for all configured queues.
  """
  @spec start_configured() :: :ok
  def start_configured do
    Enum.each(Config.queue_names(), &ensure_started/1)
    :ok
  end
end
