# Batches

Fan-out/fan-in without blocking a BEAM process.

## Pattern

1. Parent job runs (e.g. large query)
2. `Kathikon.Batch.start/3` enqueues child jobs
3. Parent moves to `:waiting_for_children` in storage
4. Each child completion updates batch counters
5. When policy is satisfied, a continuation job is enqueued (`on_complete`)

## API

```elixir
Kathikon.Batch.start(parent_id, child_specs, on_complete: {ReportWorker, args})
Kathikon.Batch.status(batch_id)
Kathikon.Batch.children(batch_id)
Kathikon.Batch.results(batch_id)
Kathikon.Batch.retry_failed(batch_id)
```

## Why not block the parent process?

Blocking would tie up dispatcher concurrency and lose durability on crash. Persisted `:waiting_for_children` survives restarts; continuation jobs keep the workflow explicit.
