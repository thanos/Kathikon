defmodule Kathikon.Backend.Storage do
  @moduledoc """
  Storage behaviour for job persistence.

  Configure the implementation via `config :kathikon, storage_backend: module`.
  Phase 1 ships `Kathikon.Backend.Storage.Mnesia`.
  """

  alias Kathikon.Job

  @callback setup() :: :ok
  @callback clear_jobs!() :: :ok
  @callback reset!() :: :ok

  @callback insert(Job.t()) :: {:ok, Job.t()} | {:error, term()}
  @callback update(Job.t()) :: {:ok, Job.t()} | {:error, term()}
  @callback fetch(String.t()) :: {:ok, Job.t()} | {:error, term()}
  @callback claim(atom(), DateTime.t()) ::
              {:ok, Job.t()} | :not_found | {:error, term()}
  @callback promote_scheduled(DateTime.t()) :: non_neg_integer()
  @callback prunable_jobs(DateTime.t()) :: [Job.t()]
  @callback delete(String.t()) :: :ok
  @callback all() :: [Job.t()]
end
