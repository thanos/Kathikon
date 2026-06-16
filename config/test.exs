import Config

config :kathikon,
  poll_interval: 50,
  scheduler_interval: 50,
  prune_interval: 60_000,
  retention_period: 1,
  max_attempts: 3,
  queues: [
    default: [concurrency: 10],
    priority: [concurrency: 1]
  ]
