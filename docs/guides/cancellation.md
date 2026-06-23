# Cancellation

Cancel jobs that have not yet finished successfully.

## API

```elixir
{:ok, cancelled} = Kathikon.cancel(job_id)
cancelled.state        # :cancelled
cancelled.cancelled_at # DateTime.utc_now() at cancel time
```

## Cancellable states

| State | Can cancel? |
|-------|-------------|
| `:scheduled` | Yes |
| `:available` | Yes |
| `:retryable` | Yes |
| `:running` | **No** — `{:error, :executing}` (legacy error name) |
| `:claimed` | **Yes** |
| `:failed` | **No** |
| `:dead` | **No** |
| `:waiting_for_children` | **No** |
| `:completed` | **No** — `{:error, {:invalid_state, :completed}}` |
| `:cancelled` | **No** — `{:error, {:invalid_state, :cancelled}}` |
| `:discarded` | **No** — `{:error, {:invalid_state, :discarded}}` |

Running jobs are not interrupted in v0.2.0. A job already in `:running` will finish even if you need to cancel it — design workers for short tasks or add cancellation checks in a future release.

## Example: cancel a scheduled newsletter

```elixir
{:ok, job} =
  Kathikon.insert(NewsletterWorker, %{"list" => "monthly"},
    schedule_in: 86_400
  )

# User unsubscribes before send
{:ok, cancelled} = Kathikon.cancel(job.id)
```

## Example: double cancel

```elixir
Kathikon.cancel(job_id)
# {:ok, %Job{state: :cancelled, ...}}

Kathikon.cancel(job_id)
# {:error, {:invalid_state, :cancelled}}
```

## Pruning

Cancelled jobs are terminal. The pruner deletes them after `retention_period`.

## Telemetry

`[:kathikon, :job, :cancel]` with metadata `%{queue: ..., job_id: ...}`.

## Related

- [Scheduling](scheduling.md) — cancel before promotion
- [Module reference: Kathikon.cancel/1](../reference/modules.md#kathikoncancel1)
