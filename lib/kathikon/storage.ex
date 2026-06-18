defmodule Kathikon.Storage do
  @moduledoc """
  Storage facade for job persistence and Mnesia lifecycle.

  Delegates to `Kathikon.Backend.Storage` (default: `Kathikon.Backend.Storage.Mnesia`).
  Application code should prefer `Kathikon.insert/3` over calling `Storage` directly.

  ## Embedding

      {:ok, _} = Application.ensure_all_started(:kathikon)
      :ok = Kathikon.Storage.setup()

  ## Tests

      :ok = Kathikon.Storage.clear_jobs!()

  Runtime processes (`Kathikon.Dispatcher`, `Kathikon.Scheduler`, `Kathikon.Pruner`)
  accept an optional `:storage` module at `start_link/1`. Facade tests can scope a
  mock backend to the test process with `set_test_backend!/1` — see
  `docs/guides/storage-and-embedding.md`.

  See `docs/guides/storage-and-embedding.md`.
  """

  alias Kathikon.Job

  @backend_key :storage_backend
  @storage_override {:kathikon, :storage_override}

  @doc """
  Ensures the storage backend schema and tables exist on the current node.

  Call this when embedding Kathikon outside `Kathikon.Application`, or when
  tests need an isolated storage bootstrap before the application starts.
  """
  @spec setup() :: :ok
  def setup, do: backend_module().setup()

  @doc false
  @spec clear_jobs!() :: :ok
  def clear_jobs!, do: backend_module().clear_jobs!()

  @doc false
  @spec reset!() :: :ok
  def reset!, do: backend_module().reset!()

  @doc false
  @spec backend() :: module()
  def backend, do: backend_module()

  @doc false
  @spec backend(module()) :: :ok
  def backend(module) when is_atom(module) do
    Application.put_env(:kathikon, @backend_key, module)
  end

  @doc false
  @spec set_test_backend!(module()) :: :ok
  def set_test_backend!(module) when is_atom(module) do
    Process.put(@storage_override, module)
    :ok
  end

  @doc false
  @spec clear_test_backend!() :: :ok
  def clear_test_backend! do
    Process.delete(@storage_override)
    :ok
  end

  @doc false
  @spec with_backend(module(), (-> term())) :: term()
  def with_backend(module, fun) when is_atom(module) and is_function(fun, 0) do
    previous = Process.get(@storage_override)
    Process.put(@storage_override, module)

    try do
      fun.()
    after
      case previous do
        nil -> Process.delete(@storage_override)
        mod -> Process.put(@storage_override, mod)
      end
    end
  end

  @doc false
  @spec insert(Job.t()) :: {:ok, Job.t()} | {:error, term()}
  def insert(job), do: backend_module().insert(job)

  @doc false
  @spec update(Job.t()) :: {:ok, Job.t()} | {:error, term()}
  def update(job), do: backend_module().update(job)

  @doc false
  @spec fetch(String.t()) :: {:ok, Job.t()} | {:error, term()}
  def fetch(id), do: backend_module().fetch(id)

  @doc false
  @spec claim(atom(), DateTime.t()) :: {:ok, Job.t()} | :not_found | {:error, term()}
  def claim(queue, now), do: backend_module().claim(queue, now)

  @doc false
  @spec promote_scheduled(DateTime.t()) :: non_neg_integer()
  def promote_scheduled(now), do: backend_module().promote_scheduled(now)

  @doc false
  @spec prunable_jobs(DateTime.t()) :: [Job.t()]
  def prunable_jobs(cutoff), do: backend_module().prunable_jobs(cutoff)

  @doc false
  @spec delete(String.t()) :: :ok
  def delete(id), do: backend_module().delete(id)

  @doc false
  @spec all() :: [Job.t()]
  def all, do: backend_module().all()

  defp backend_module do
    Process.get(@storage_override) ||
      Application.get_env(:kathikon, @backend_key, Kathikon.Backend.Storage.Mnesia)
  end
end
