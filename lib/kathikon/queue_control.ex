defmodule Kathikon.QueueControl do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc false
  def pause(queue) when is_atom(queue), do: GenServer.call(@name, {:pause, queue})

  @doc false
  def resume(queue) when is_atom(queue), do: GenServer.call(@name, {:resume, queue})

  @doc false
  def paused?(queue) when is_atom(queue), do: GenServer.call(@name, {:paused?, queue})

  @doc false
  def status(queue) when is_atom(queue), do: GenServer.call(@name, {:status, queue})

  @impl true
  def init(_opts), do: {:ok, %{paused: MapSet.new()}}

  @impl true
  def handle_call({:pause, queue}, _from, state) do
    {:reply, :ok, %{state | paused: MapSet.put(state.paused, queue)}}
  end

  def handle_call({:resume, queue}, _from, state) do
    {:reply, :ok, %{state | paused: MapSet.delete(state.paused, queue)}}
  end

  def handle_call({:paused?, queue}, _from, state) do
    {:reply, MapSet.member?(state.paused, queue), state}
  end

  def handle_call({:status, queue}, _from, state) do
    paused = MapSet.member?(state.paused, queue)
    {:reply, %{queue: queue, paused: paused}, state}
  end
end
