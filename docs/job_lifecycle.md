# Job lifecycle

States are enforced by `Kathikon.Job.StateMachine`. Invalid transitions return `{:error, {:invalid_transition, from, to}}`.

## States

| State | Meaning |
|-------|---------|
| `:scheduled` | Waiting until `scheduled_at` |
| `:available` | Ready to claim |
| `:claimed` | Atomically claimed |
| `:running` | Worker executing |
| `:retryable` | Failed, waiting for backoff |
| `:waiting_for_children` | Batch parent waiting on children |
| `:completed` | Success |
| `:failed` | Terminal failure (retries exhausted) |
| `:dead` | Dead-letter queue |
| `:cancelled` | Cancelled before completion |
| `:discarded` | Permanently discarded |

## Worker return values

| Return | Effect |
|--------|--------|
| `:ok` / `{:ok, result}` | Complete; result stored per `result:` option |
| `{:error, reason}` | Retry with backoff; dead-letter after max attempts |
| `{:discard, reason}` | Move to `:discarded` |
| `{:retry, reason}` | Same as error (explicit retry) |
| `{:sleep, seconds}` | Reschedule without incrementing attempts |

## History

Every transition writes a durable event retrievable via `Kathikon.history/1`.
