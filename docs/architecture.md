# Architecture

```
Kathikon.Supervisor
├── Registry
├── Kathikon.Queue (DynamicSupervisor → Dispatcher per queue)
├── Kathikon.QueueControl (pause/resume)
├── Kathikon.Scheduler.Promoter (scheduled → available)
└── Kathikon.Pruner
```

Scheduling adapters (`Kathikon.Scheduler.BuiltIn`, optional `Kathikon.Scheduler.Quantum`) enqueue durable jobs; they do not execute workers directly.

Storage behaviour: `Kathikon.Storage` → default `Kathikon.Storage.Mnesia`.

See `docs/v0_2_0_architecture_review.md` for the v0.1.0 → v0.2.0 analysis.
