# Kathikon v0.2.0 Architecture Review

This document reviews the v0.1.0 codebase before the v0.2.0 correctness and control release.

## Current Supervision Tree

```
Kathikon.Supervisor
├── Registry (Kathikon.Registry)
├── Kathikon.Queue (DynamicSupervisor)
│   └── Kathikon.Dispatcher (one per queue)
├── Kathikon.Scheduler.Promoter (promotes scheduled → available)
└── Kathikon.Pruner (deletes terminal jobs past retention)
```

v0.2.0 adds optional scheduler adapter processes via `Kathikon.Scheduler.BuiltIn` and optional Quantum integration. Batch coordination is storage-backed; no extra OTP processes are required for parent/child waits.

## Current Storage Design

v0.1.0 used:

- `Kathikon.Storage` — behaviour and facade delegating to a configurable backend module
- `Kathikon.Storage.Mnesia` — Mnesia tables storing `:erlang.term_to_binary/1` payloads

v0.2.0 expands the `Kathikon.Storage` behaviour with atomic lifecycle operations, a `:kathikon_history` table, batch records, and dead-letter support. `Kathikon.Backend.Storage` modules remain as deprecated compatibility aliases.

## Current Job Lifecycle

v0.1.0 states: `:scheduled`, `:available`, `:executing`, `:retryable`, `:completed`, `:cancelled`, `:discarded`.

Claiming jumped directly from `:available` to `:executing` inside a Mnesia transaction (safe for queue-level claim, but no explicit `:claimed` / `:running` split or per-job claim API).

v0.2.0 adds `:claimed`, `:running` (replacing `:executing`), `:failed`, `:dead`, and `:waiting_for_children`, enforced by `Kathikon.Job.StateMachine`.

## Dispatcher / Worker Design

The dispatcher polls on an interval, atomically claims up to `concurrency` slots, and spawns `Task`s to run workers. Results are persisted via `Storage.update/1` from the dispatcher process — a read-modify-write at the application layer after execution, not an atomic storage transition.

v0.2.0 routes completions, failures, retries, and discards through storage callbacks (`complete_job/3`, `fail_job/3`, etc.) and records durable history events.

## Scheduling Support

v0.1.0 supported `schedule_in` and `schedule_at` on insert. A promoter GenServer periodically calls `promote_scheduled/1`. `Kathikon.Cron` was a stub.

v0.2.0 adds `Kathikon.schedule/3`, a scheduler behaviour, built-in delayed/recurring registration, and optional Quantum adapter.

## Retry Behavior

Exponential backoff via `Job.backoff_seconds/1`. After `max_attempts`, jobs were marked `:discarded`.

v0.2.0 moves exhausted jobs to `:failed` then `:dead` (dead-letter queue) with explicit retry/rerun APIs.

## Result / Error Persistence

v0.1.0 stored errors in a list on the job struct; results were not persisted. v0.2.0 adds `result`, `last_error`, timestamp fields, and configurable result storage (`:store` | `:discard`).

## Management APIs

v0.1.0 exposed `insert/3`, `cancel/1`, `fetch/1`, and `all/0`. v0.2.0 adds status, retry, rerun, queue pause/resume, dead-letter, reporting, and batch APIs.

## Documentation Gaps

v0.1.0 lacked docs for storage behaviour boundaries, atomic claiming, dead-letter semantics, batches, Quantum adapter, and reporting. v0.2.0 adds dedicated guides under `docs/`.

## Risks in v0.1.0

1. **Post-execution update** — dispatcher mutates job struct and calls `update/1`; concurrent management operations could race (mitigated by v0.2.0 atomic storage ops).
2. **Queue claim scans all jobs** — O(n) per claim; acceptable for Phase 1 scale, documented as a limitation.
3. **Term storage in Mnesia** — arbitrary Elixir terms in payloads; documented tradeoffs in `docs/storage.md`.
4. **No audit trail** — terminal jobs are pruned; v0.2.0 history events survive until pruned with the job.

## Claiming Safety

Queue-level `claim/2` in v0.1.0 **was** inside a Mnesia transaction (not an unsafe read-then-update across transactions). However, there was no per-job `claim_job/2`, no `:claimed` state, and no concurrency test for single-job claims. v0.2.0 adds atomic per-job claiming and `claim_available/2`.
