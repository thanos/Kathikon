import Config

config :kathikon,
  queues: [default: [concurrency: 10]],
  poll_interval: 200,
  scheduler_interval: 1_000,
  prune_interval: 60_000,
  retention_period: :timer.hours(24 * 7),
  max_attempts: 20,
  storage_backend: Kathikon.Backend.Storage.Mnesia

import_config "#{config_env()}.exs"
