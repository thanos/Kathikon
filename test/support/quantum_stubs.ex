defmodule Kathikon.QuantumSchedulerStub do
  @moduledoc false

  def add_job(name, _opts), do: {:ok, name}
  def delete_job(_name), do: :ok

  def jobs do
    [%{name: :listed_job, schedule: "0 * * * *", state: :active}]
  end
end
