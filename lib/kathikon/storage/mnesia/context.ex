defmodule Kathikon.Storage.Mnesia.Context do
  @moduledoc """
  Transaction boundary for `Kathikon.Storage.Mnesia`.

  Defaults to `:mnesia`. Tests may inject a Mox double via
  `config :kathikon, mnesia_context: MyMock`.
  """

  @callback transaction((-> term())) :: term()
  @callback abort(term()) :: no_return()

  @doc false
  def transaction(fun) when is_function(fun, 0), do: impl().transaction(fun)

  @doc false
  def abort(reason), do: impl().abort(reason)

  defp impl do
    Application.get_env(:kathikon, :mnesia_context, Kathikon.Storage.Mnesia.Context.Default)
  end
end

defmodule Kathikon.Storage.Mnesia.Context.Default do
  @moduledoc false
  @behaviour Kathikon.Storage.Mnesia.Context

  @dialyzer {:no_return, abort: 1}

  @impl true
  def transaction(fun), do: :mnesia.transaction(fun)

  @impl true
  def abort(reason), do: :mnesia.abort(reason)
end
