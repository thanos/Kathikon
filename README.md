# Kathikon

**Kathikon** (Greek: καθήκον — duty, obligation) is a BEAM-native durable job queue and task execution platform for Elixir.

Jobs are treated as durable obligations that must eventually be fulfilled: completed, retried, cancelled, or discarded — but never silently lost.

Kathikon uses **Mnesia** as its coordination store and **OTP** as its execution substrate. No PostgreSQL, Redis, RabbitMQ, or external brokers are required.

## Status

**v0.1.0 — Phase 1: Durable Job Queue**

- Job insertion and queue execution
- Retries with exponential backoff
- Scheduling (`schedule_in`, `schedule_at`)
- Priorities
- Telemetry
- Pruning / retention

## Installation

```elixir
def deps do
  [
    {:kathikon, "~> 0.1.0"}
  ]
end
```

## Quick start

Define a worker:

```elixir
defmodule MyApp.EmailWorker do
  use Kathikon.Worker

  @impl true
  def perform(%Kathikon.Job{args: %{"email" => email}}) do
    MyApp.Mailer.deliver(email)
    :ok
  end
end
```

Configure queues:

```elixir
# config/config.exs
config :kathikon,
  queues: [
    default: [concurrency: 10],
    emails: [concurrency: 5]
  ]
```

Enqueue jobs:

```elixir
{:ok, job} = Kathikon.insert(MyApp.EmailWorker, %{"email" => "user@example.com"})

{:ok, job} =
  Kathikon.insert(MyApp.EmailWorker, %{"email" => "user@example.com"},
    queue: :emails,
    priority: 5,
    schedule_in: 60,
    max_attempts: 10
  )
```

Cancel a pending job:

```elixir
{:ok, job} = Kathikon.cancel(job_id)
```

## Architecture

```
Kathikon.Supervisor
├── Registry
├── Kathikon.Queue (DynamicSupervisor)
│   └── Kathikon.Dispatcher (one per queue)
├── Kathikon.Scheduler
└── Kathikon.Pruner
```

| Module | Role |
|--------|------|
| `Kathikon.Job` | Job struct and state machine |
| `Kathikon.Worker` | Worker behaviour (`perform/1`) |
| `Kathikon.Storage` | Mnesia persistence and atomic claims |
| `Kathikon.Dispatcher` | Claims and executes jobs per queue |
| `Kathikon.Scheduler` | Promotes scheduled jobs to available |
| `Kathikon.Pruner` | Enforces retention on terminal jobs |
| `Kathikon.Telemetry` | `[:kathikon, ...]` telemetry events |

## Job states

```
scheduled → available → executing → completed
                    ↘           ↘ retryable → ...
                      cancelled   discarded
```

## Telemetry

Kathikon emits standard telemetry events:

- `[:kathikon, :job, :insert]`
- `[:kathikon, :job, :start]`
- `[:kathikon, :job, :stop]`
- `[:kathikon, :job, :retry]`
- `[:kathikon, :job, :discard]`
- `[:kathikon, :job, :cancel]`
- `[:kathikon, :job, :prune]`

Attach the default logger in development:

```elixir
Kathikon.Telemetry.attach_default_logger()
```

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `:queues` | `[default: [concurrency: 10]]` | Queue names and concurrency |
| `:poll_interval` | `200` | Dispatcher poll interval (ms) |
| `:scheduler_interval` | `1000` | Scheduler tick interval (ms) |
| `:prune_interval` | `60000` | Pruner tick interval (ms) |
| `:retention_period` | `7 days` | How long to keep terminal jobs (ms) |
| `:max_attempts` | `20` | Default retry limit |
| `:mnesia_copies` | `:auto` | Mnesia storage: `:ram`, `:disc`, or `:auto` (`ram` on `nonode@nohost` and Livebook nodes) |

## Roadmap

| Phase | Focus |
|-------|-------|
| 1 | Durable job queue (current) |
| 2 | Distributed coordination, leases, lifeline |
| 3 | Cron, uniqueness, dynamic queues |
| 4 | Rate limits, pause/resume |
| 5 | Batches |
| 6 | Observability APIs |
| 7 | Workflows and DAGs |
| 8 | Optional LiveView dashboard |

## Documentation

Generate HTML docs with [ExDoc](https://github.com/elixir-lang/ex_doc):

```bash
mix docs
open doc/index.html
```

- **[Documentation index](docs/documentation.md)** — guides and module reference (source)
- [Quick start](docs/guides/quick-start.md)
- [Module reference](docs/reference/modules.md)
- [Configuration](docs/guides/configuration.md)
- [Interactive demo (Livebook)](livebooks/kathikon_demo.livemd)
- [Phase 1 implementation plan](plans/phase-1.md)
- [Phase 1 concepts](docs/phase-1-concepts.md)
- [Phase 1 operations](docs/phase-1-operations.md)

## License

Apache 2.0 (placeholder — add license file before publishing)
