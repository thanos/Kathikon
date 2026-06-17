# Configuration

All options are set under `config :kathikon, ...`.

## Full example

```elixir
# config/config.exs
config :kathikon,
  queues: [
    default: [concurrency: 10],
    emails: [concurrency: 5],
    reports: [concurrency: 2]
  ],
  poll_interval: 200,
  scheduler_interval: 1_000,
  prune_interval: 60_000,
  retention_period: :timer.hours(24 * 7),
  max_attempts: 20,
  mnesia_copies: :auto,
  storage_backend: Kathikon.Backend.Storage.Mnesia
```

## Options reference

| Key | Default | Description |
|-----|---------|-------------|
| `:queues` | `[default: [concurrency: 10]]` | Queue names and per-queue options |
| `:poll_interval` | `200` | Dispatcher poll period (ms) |
| `:scheduler_interval` | `1000` | Scheduler tick period (ms) |
| `:prune_interval` | `60000` | Pruner tick period (ms) |
| `:retention_period` | `604800000` (7 days) | How long to keep terminal jobs (ms) |
| `:max_attempts` | `20` | Default retry limit for new jobs |
| `:mnesia_copies` | `:auto` | Mnesia table storage — `:ram`, `:disc`, or `:auto` |
| `:storage_backend` | `Kathikon.Backend.Storage.Mnesia` | Storage behaviour implementation |

### Queue options

Each queue entry is a keyword list:

```elixir
[concurrency: 10]   # max simultaneous Task workers
```

Access at runtime:

```elixir
Kathikon.Config.queue_names()      # [:default, :emails, ...]
Kathikon.Config.concurrency(:emails) # 5
Kathikon.Config.queue_config(:emails)
```

### mnesia_copies

| Value | Behaviour |
|-------|-----------|
| `:auto` | `ram` on `nonode@nohost` and Livebook nodes; `disc` on other named nodes |
| `:ram` | In-memory tables — dev, test, Livebook |
| `:disc` | Durable on disk — production named nodes |

```elixir
# Livebook / local scripts
config :kathikon, mnesia_copies: :ram
```

## Environment-specific overrides

```elixir
# config/test.exs
import Config

config :kathikon,
  poll_interval: 50,
  scheduler_interval: 50,
  retention_period: 1,
  max_attempts: 3,
  queues: [default: [concurrency: 10], priority: [concurrency: 1]]
```

## Reading config in code

```elixir
Kathikon.Config.poll_interval()
Kathikon.Config.retention_period()
Kathikon.Config.mnesia_copies()
```

## Related

- [Storage & embedding](storage-and-embedding.md)
- [Module reference: Kathikon.Config](../reference/modules.md#kathikonconfig)
