# Kathikon documentation

Kathikon (καθήκον — duty, obligation) is a BEAM-native durable job queue for Elixir. Jobs are persisted in Mnesia, executed by OTP supervisors and dispatchers, and tracked through an explicit state machine.

**Current release:** v0.1.0 — Phase 1 (durable job queue)

## Guides

Start here if you are new to the library:

| Guide | What you will learn |
|-------|---------------------|
| [Quick start](guides/quick-start.md) | Install, configure, define a worker, enqueue your first job |
| [Workers](guides/workers.md) | The `Kathikon.Worker` behaviour, return values, errors |
| [Queues & concurrency](guides/queues-and-concurrency.md) | Multiple queues, dispatcher concurrency, isolation |
| [Scheduling](guides/scheduling.md) | `schedule_in`, `schedule_at`, scheduler promotion |
| [Retries & errors](guides/retries-and-errors.md) | Backoff, `max_attempts`, discard, error recording |
| [Cancellation](guides/cancellation.md) | When jobs can be cancelled, API usage |
| [Telemetry](guides/telemetry-and-observability.md) | Events, measurements, metadata, custom handlers |
| [Configuration](guides/configuration.md) | All `config :kathikon` keys and environments |
| [Storage & embedding](guides/storage-and-embedding.md) | Mnesia setup, Livebook, tests, backends |

## Reference

| Document | Contents |
|----------|----------|
| [Module reference](reference/modules.md) | Every module and public function with examples |
| [Phase 1 concepts](phase-1-concepts.md) | Design rationale (OTP, Mnesia, obligations) |
| [Phase 1 operations](phase-1-operations.md) | Operational notes for running in production |
| [Interactive demo](../livebooks/kathikon_demo.livemd) | Livebook walkthrough of Phase 1 features |

## Architecture at a glance

```
Kathikon.Supervisor
├── Registry
├── Kathikon.Queue          (DynamicSupervisor → one Dispatcher per queue)
├── Kathikon.Scheduler      (promotes :scheduled → :available)
└── Kathikon.Pruner         (deletes terminal jobs after retention)
```

Public API: `Kathikon.insert/3`, `Kathikon.cancel/1`, `Kathikon.fetch/1`, `Kathikon.all/0`, `Kathikon.start_queue/1`.
