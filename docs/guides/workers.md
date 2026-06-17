# Workers

Workers are modules that implement `Kathikon.Worker`. The dispatcher calls `perform/1` when a job is claimed.

## Defining a worker

```elixir
defmodule MyApp.Workers.ChargeCustomer do
  use Kathikon.Worker

  @impl true
  def perform(%Kathikon.Job{args: %{"invoice_id" => id}} = job) do
  #  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  #  `job` includes id, queue, attempts, priority, timestamps, errors

    case MyApp.Billing.charge(id) do
      :ok -> :ok
      {:error, :card_declined} -> {:error, :card_declined}
    end
  end
end
```

`use Kathikon.Worker` sets `@behaviour Kathikon.Worker`. You must implement `perform/1`.

## Return values

| Return | Effect |
|--------|--------|
| `:ok` | Job → `:completed` |
| `{:sleep, seconds}` | Job → `:scheduled` for `seconds`; not a failure (no `attempts` or `errors`) |
| `{:error, reason}` | Job → `:retryable` with backoff, or `:discarded` if `max_attempts` exceeded |

```elixir
# Success
:ok

# Defer without failure — scheduler promotes back to :available when due
{:sleep, 60}
{:sleep, 300}

# Transient failure — will retry (increments attempts, records error)
{:error, :timeout}
{:error, %{status: 503}}

# Any term is accepted as the error reason
{:error, "payment gateway unavailable"}
```

`{:sleep, seconds}` requires a positive integer. Invalid values are treated as `{:error, {:invalid_sleep, value}}`.

## Exceptions and throws

Uncaught exceptions and throws are converted to `{:error, reason}` internally:

```elixir
def perform(_job), do: raise("boom")      # → retry as {:exception, ...}
def perform(_job), do: throw(:cancelled)  # → retry as {:throw, :cancelled}
```

Design workers to return `{:error, reason}` for expected failures; reserve exceptions for programmer errors.

## Enqueueing work for a worker

```elixir
{:ok, job} =
  Kathikon.insert(MyApp.Workers.ChargeCustomer, %{"invoice_id" => "INV-99"},
    queue: :billing,
    max_attempts: 5,
    priority: 3
  )
```

Args must be a **map** (JSON-serializable values work best for future cross-node support).

## Idempotency

Kathikon provides **at-least-once** execution. A worker may run more than once for the same job id (retries, future lease recovery). Make `perform/1` safe to repeat:

```elixir
def perform(%{args: %{"order_id" => id}}) do
  # Good: billing API keyed by order_id is idempotent
  MyApp.Billing.capture_once(id)
  :ok
end
```

## IO-bound vs CPU-bound work

- **IO-bound** (HTTP, email, DB): higher concurrency per queue is fine.
- **CPU-bound** (PDF, image processing): use a dedicated queue with low concurrency.

See [Queues & concurrency](queues-and-concurrency.md).

## Related

- `Kathikon.Worker` module — behaviour definition
- [Retries & errors](retries-and-errors.md)
- [Module reference: Kathikon.Worker](../reference/modules.md#kathikonworker)
