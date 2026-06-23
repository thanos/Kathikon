defmodule Kathikon.Scheduler.Quantum do
  @moduledoc """
  Optional Quantum scheduler adapter.

  Quantum decides when recurring schedules fire. Kathikon owns durable job
  creation, execution, history, retry, dead-letter, batches, and reporting.

  ## Configuration

      config :kathikon,
        scheduler: Kathikon.Scheduler.Quantum,
        quantum_scheduler: MyApp.KathikonScheduler

  ## Example user scheduler

      defmodule MyApp.KathikonScheduler do
        use Quantum, otp_app: :my_app
      end

  See `docs/quantum_adapter.md`.
  """

  @compile {:no_warn_undefined, [Quantum]}

  @behaviour Kathikon.Scheduler.Behaviour

  alias Kathikon.Cron.Expression
  alias Kathikon.Scheduler.BuiltIn

  @doc false
  def available? do
    case Application.get_env(:kathikon, :quantum_available) do
      nil -> Code.ensure_loaded?(Quantum)
      fun when is_function(fun, 1) -> fun.(Quantum)
      bool when is_boolean(bool) -> bool
    end
  end

  @doc """
  Schedules a one-time job via the built-in scheduler when Quantum is available.

  Returns `{:error, :quantum_not_available}` when the Quantum dependency is
  not loaded, or `{:error, :quantum_scheduler_not_configured}` when no scheduler
  module is configured.
  """
  @impl true
  def schedule_once(worker, args, opts) do
    with :ok <- ensure_quantum!(),
         :ok <- ensure_scheduler_module!() do
      BuiltIn.schedule_once(worker, args, opts)
    end
  end

  @doc """
  Registers a recurring cron schedule with Quantum when available.

  Returns `{:error, :quantum_not_available}` when the Quantum dependency is
  not loaded, or `{:error, :quantum_scheduler_not_configured}` when no scheduler
  module is configured.
  """
  @impl true
  def schedule_recurring(worker, args, opts) do
    cron = Keyword.fetch!(opts, :cron)

    with {:ok, _} <- Expression.parse(cron),
         :ok <- ensure_quantum!(),
         :ok <- ensure_scheduler_module!(),
         scheduler <- quantum_scheduler_module() do
      job_name = Keyword.get(opts, :name, generate_name(worker))

      schedule_opts = [
        schedule: cron,
        task: {__MODULE__, :enqueue, [worker, args, Keyword.drop(opts, [:cron, :name])]},
        run_strategy: Quantum.RunStrategy.Local
      ]

      case scheduler.add_job(job_name, schedule_opts) do
        {:ok, _} -> {:ok, job_name}
        {:error, reason} -> {:error, reason}
        other -> {:ok, other}
      end
    end
  end

  @doc """
  Updates the cron expression on a Quantum recurring schedule when supported.
  """
  @impl true
  def update_schedule(schedule_id, opts) do
    cron = Keyword.get(opts, :cron)

    with :ok <- validate_cron_change(cron),
         :ok <- ensure_quantum!(),
         :ok <- ensure_scheduler_module!(),
         scheduler <- quantum_scheduler_module(),
         true <- function_exported?(scheduler, :update_job, 2),
         {:ok, job} <- scheduler.update_job(schedule_id, schedule: cron) do
      {:ok, quantum_schedule_map(job)}
    else
      false -> {:error, :not_supported}
      other -> other
    end
  end

  @doc """
  Fetches a recurring schedule from the configured Quantum scheduler.
  """
  @impl true
  def fetch_schedule(schedule_id) do
    with :ok <- ensure_quantum!(),
         :ok <- ensure_scheduler_module!(),
         scheduler <- quantum_scheduler_module() do
      if function_exported?(scheduler, :fetch_job, 1) do
        fetch_quantum_schedule(scheduler, schedule_id)
      else
        find_quantum_schedule(scheduler, schedule_id)
      end
    end
  end

  defp fetch_quantum_schedule(scheduler, schedule_id) do
    case scheduler.fetch_job(schedule_id) do
      {:ok, job} -> {:ok, quantum_schedule_map(job)}
      other -> other
    end
  end

  defp find_quantum_schedule(scheduler, schedule_id) do
    case Enum.find(scheduler.jobs(), &(&1.name == schedule_id)) do
      nil -> {:error, :not_found}
      job -> {:ok, quantum_schedule_map(job)}
    end
  end

  defp quantum_schedule_map(job) do
    %{id: job.name, cron: job.schedule, state: job.state}
  end

  @doc """
  Removes a recurring schedule from the configured Quantum scheduler.
  """
  @impl true
  def cancel_schedule(schedule_id) do
    with :ok <- ensure_quantum!(),
         :ok <- ensure_scheduler_module!(),
         scheduler <- quantum_scheduler_module() do
      scheduler.delete_job(schedule_id)
      :ok
    end
  end

  @doc """
  Lists recurring schedules registered with the configured Quantum scheduler.
  """
  @impl true
  def list_schedules(_opts \\ []) do
    with :ok <- ensure_quantum!(),
         :ok <- ensure_scheduler_module!(),
         scheduler <- quantum_scheduler_module() do
      jobs =
        scheduler.jobs()
        |> Enum.map(fn job ->
          %{
            id: job.name,
            schedule: job.schedule,
            state: job.state
          }
        end)

      {:ok, jobs}
    end
  end

  @doc false
  def enqueue(worker, args, opts) when is_atom(worker) do
    Kathikon.insert(worker, args, opts)
  end

  defp ensure_quantum! do
    if available?(), do: :ok, else: {:error, :quantum_not_available}
  end

  defp ensure_scheduler_module! do
    case Application.get_env(:kathikon, :quantum_scheduler) do
      nil ->
        {:error, :quantum_scheduler_not_configured}

      mod when is_atom(mod) ->
        if Code.ensure_loaded?(mod), do: :ok, else: {:error, :quantum_scheduler_not_loaded}
    end
  end

  defp quantum_scheduler_module do
    Application.get_env(:kathikon, :quantum_scheduler)
  end

  defp generate_name(worker) do
    "kathikon_#{inspect(worker)}_#{System.unique_integer([:positive])}"
  end

  defp validate_cron_change(nil), do: {:error, :missing_cron}

  defp validate_cron_change(cron) do
    if match?({:ok, _}, Expression.parse(cron)), do: :ok, else: {:error, :invalid_cron}
  end
end
