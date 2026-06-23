import Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :kathikon,
  timezone: "Etc/UTC",
  queues: [default: [concurrency: 10]],
  poll_interval: 200,
  scheduler_interval: 1_000,
  prune_interval: 60_000,
  retention_period: :timer.hours(24 * 7),
  max_attempts: 20,
  storage_backend: Kathikon.Backend.Storage.Mnesia

import_config "#{config_env()}.exs"
