defmodule Kathikon.Mnesia.Backend do
  @moduledoc false

  @callback start() :: :ok | {:error, term()}
  @callback stop() :: :ok | {:error, term()}
  @callback system_info(atom()) :: term()
  @callback create_schema([node()]) :: :ok | {:error, term()}
  @callback create_table(atom(), keyword()) :: term()
  @callback wait_for_tables([atom()], pos_integer()) ::
              :ok | {:timeout, [atom()]} | {:error, term()}
  @callback clear_table(atom()) :: :ok
  @callback delete_table(atom()) :: :ok | {:error, term()}
end
