defmodule Kathikon.Workers.SuccessWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(_job), do: :ok
end

defmodule Kathikon.Workers.FailWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(_job), do: {:error, :failed}
end

defmodule Kathikon.Workers.CountingWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(job) do
    if job.attempts + 1 >= 2 do
      :ok
    else
      {:error, :not_yet}
    end
  end
end

defmodule Kathikon.Workers.PriorityWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(job) do
    Kathikon.TestSupport.record_order(job.args["label"])
    :ok
  end
end

defmodule Kathikon.Workers.SleepWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(job) do
    {:sleep, job.args["seconds"] || 30}
  end
end

defmodule Kathikon.Workers.RaiseWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(_job), do: raise("boom")
end

defmodule Kathikon.Workers.ThrowWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(_job), do: throw(:thrown)
end

defmodule Kathikon.Workers.ExitWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(_job), do: exit(:shutdown)
end
