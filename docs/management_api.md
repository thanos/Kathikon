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
