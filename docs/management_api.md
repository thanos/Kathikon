# Management API

Operational functions return tagged tuples for dashboard use.

```elixir
Kathikon.status(job_id)
Kathikon.cancel(job_id, reason)
Kathikon.retry(job_id, opts)
Kathikon.rerun(job_id, opts)
Kathikon.pause_queue(queue)
Kathikon.resume_queue(queue)
Kathikon.queue_status(queue)
Kathikon.children(job_id)
Kathikon.result(job_id)
Kathikon.errors(job_id)
Kathikon.dead_jobs(opts)
Kathikon.retry_dead(job_id, opts)
Kathikon.discard_dead(job_id, reason)
Kathikon.history(job_id)
```

## Rerun semantics

`Kathikon.rerun/2` creates a **new** linked job. The original record is unchanged. The new job sets `rerun_of` and `original_job_id` for audit trails.

## Dashboard facade

`Kathikon.Dashboard` wraps reporting and management for CLIs, LiveView, and RPC:

```elixir
{:ok, queues} = Kathikon.Dashboard.queue_summary()
{:ok, page} = Kathikon.Dashboard.list_jobs(queue: :default, tab: :completed, limit: 50)
{:ok, detail} = Kathikon.Dashboard.fetch_job(job_id)
:ok = Kathikon.Dashboard.pause_all()
```

CLI: `mix kathikon.ops summary`

Remote: `mix kathikon.ops --node kathikon@host summary` (via `Kathikon.Dashboard.RPC`).
