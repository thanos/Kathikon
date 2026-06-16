defmodule Kathikon.Workers.SuccessWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(_job) do
    :ok
  end
end

defmodule Kathikon.Workers.FailWorker do
  @moduledoc false
  use Kathikon.Worker

  @impl true
  def perform(_job) do
    {:error, :failed}
  end
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
