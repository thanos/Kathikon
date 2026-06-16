defmodule Kathikon.Config do
  @moduledoc """
  Runtime configuration for Kathikon.

  Configure via `config :kathikon, ...` in your application.
  """

  @default_queues [default: [concurrency: 10]]
  @default_poll_interval 200
  @default_scheduler_interval 1_000
  @default_prune_interval 60_000
  @default_retention_period :timer.hours(24 * 7)
  @default_max_attempts 20

  def queues, do: get(:queues, @default_queues)

  def queue_names do
    queues() |> Keyword.keys()
  end

  def queue_config(queue) do
    Keyword.get(queues(), queue, concurrency: 10)
  end

  def concurrency(queue) do
    queue_config(queue) |> Keyword.get(:concurrency, 10)
  end

  def poll_interval, do: get(:poll_interval, @default_poll_interval)

  def scheduler_interval, do: get(:scheduler_interval, @default_scheduler_interval)

  def prune_interval, do: get(:prune_interval, @default_prune_interval)

  def retention_period, do: get(:retention_period, @default_retention_period)

  def max_attempts, do: get(:max_attempts, @default_max_attempts)

  defp get(key, default) do
    Application.get_env(:kathikon, key, default)
  end
end
