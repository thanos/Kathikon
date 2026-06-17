defmodule Kathikon.Storage do
  @moduledoc false

  alias Kathikon.Job

  @backend_key :storage_backend

  @doc false
  @spec backend() :: module()
  def backend do
    Application.get_env(:kathikon, @backend_key, Kathikon.Storage.Mnesia)
  end

  @doc false
  @spec backend(module()) :: :ok
  def backend(module) when is_atom(module) do
    Application.put_env(:kathikon, @backend_key, module)
  end

  @spec insert(Job.t()) :: {:ok, Job.t()} | {:error, term()}
  def insert(job), do: backend().insert(job)

  @spec update(Job.t()) :: {:ok, Job.t()} | {:error, term()}
  def update(job), do: backend().update(job)

  @spec fetch(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def fetch(id), do: backend().fetch(id)

  @spec claim(atom(), DateTime.t()) :: {:ok, Job.t()} | :not_found | {:error, term()}
  def claim(queue, now), do: backend().claim(queue, now)

  @spec promote_scheduled(DateTime.t()) :: non_neg_integer()
  def promote_scheduled(now), do: backend().promote_scheduled(now)

  @spec scheduled_jobs(DateTime.t()) :: [Job.t()]
  def scheduled_jobs(now), do: backend().scheduled_jobs(now)

  @spec prunable_jobs(DateTime.t()) :: [Job.t()]
  def prunable_jobs(cutoff), do: backend().prunable_jobs(cutoff)

  @spec delete(String.t()) :: :ok
  def delete(id), do: backend().delete(id)

  @spec all() :: [Job.t()]
  def all, do: backend().all()

  @spec register_queue(atom(), keyword()) :: :ok
  def register_queue(name, config), do: backend().register_queue(name, config)
end
