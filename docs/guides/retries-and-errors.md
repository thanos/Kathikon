# Retries and errors

Failed jobs are retried with exponential backoff until `max_attempts` is reached, then moved to the dead-letter queue (`:dead`).

To defer a job **without** counting as a failure, return `{:sleep, seconds}` from `perform/1` instead — see [Workers](workers.md).

## Triggering a retry

Return `{:error, reason}` from `perform/1`:

```elixir
def perform(%{args: %{"url" => url}}) do
  case HTTPoison.get(url) do
    {:ok, %{status_code: 200}} -> :ok
    {:ok, %{status_code: code}} -> {:error, {:http, code}}
    {:error, reason} -> {:error, reason}
  end
end
```

## Backoff formula

`Kathikon.Job.backoff_seconds/1` computes delay before the next attempt:

| Attempt | Backoff (seconds) |
|---------|-------------------|
| 1 | 5 |
| 2 | 20 |
| 3 | 45 |
| 4 | 80 |
| … | `min(attempt² × 5, 86400)` |

After failure, the job moves to `:retryable` with `available_at` set to `now + backoff`. The dispatcher claims it again when `available_at` has passed.

```elixir
Kathikon.Job.backoff_seconds(1)  # 5
Kathikon.Job.backoff_seconds(3)  # 45
```

## max_attempts

Default comes from config (`20`). Override per job:

```elixir
Kathikon.insert(FlakyWorker, %{}, max_attempts: 3)
```

Lifecycle:

```
:running → {:error, _} → :retryable → … → :failed → :dead (attempts >= max_attempts)
```

## Dead-letter queue

When retries are exhausted, jobs move to `:dead`:

```elixir
{:ok, jobs} = Kathikon.dead_jobs()
{:ok, rerun} = Kathikon.retry_dead(job_id)
{:ok, _} = Kathikon.discard_dead(job_id, :manual_cleanup)
```

## Error history

Each failure appends to `job.errors`:

```elixir
{:ok, job} = Kathikon.fetch(job_id)

job.errors
# [
#   %{
#     "at" => "2026-06-17T12:00:00Z",
#     "attempt" => 1,
#     "reason" => ":timeout"
#   }
# ]
```

## Discarded jobs

Workers can return `{:discard, reason}` for intentional permanent failure. Discarded jobs are pruned after `retention_period` — see [Configuration](configuration.md).

## Exceptions

Raised exceptions are caught and stored as errors:

```elixir
def perform(_), do: raise("unexpected nil")
# → {:error, {:exception, %RuntimeError{}, stacktrace}}
```

## Orphaned running jobs (Phase 2)

If the worker process crashes hard or the node dies while a job is `:running`, it stays in that state until Phase 2 **lifeline** recovery. Plan workers and `max_attempts` accordingly.

## Telemetry

| Event | When |
|-------|------|
| `[:kathikon, :job, :retry]` | Failure with attempts remaining |
| `[:kathikon, :job, :discard]` | `max_attempts` exceeded |
| `[:kathikon, :job, :stop]` | Success (`result: :ok` in metadata) |

## Related

- [Workers](workers.md)
- [Telemetry](telemetry-and-observability.md)
