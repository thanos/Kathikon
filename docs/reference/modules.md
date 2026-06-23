# Module reference

Public API and runtime modules for Kathikon v0.2.0. For narrative guides see the [documentation index](../documentation.html) or [quick start](../guides/quick-start.html).

---

## Kathikon

Main entry point. Enqueue, cancel, and inspect jobs.

### `insert/3`

```elixir
@spec insert(module(), map(), keyword()) :: {:ok, Job.t()} | {:error, term()}
```

Enqueues a job. Starts the target queue dispatcher if needed. Emits `[:kathikon, :job, :inserted]`.

**Options**

| Option | Default | Description |
|--------|---------|-------------|
| `:queue` | `:default` | Target queue atom |
| `:priority` | `0` | Higher values claim first |
| `:max_attempts` | `Kathikon.Config.max_attempts()` | Retry limit |
| `:schedule_in` | — | Seconds until available |
| `:schedule_at` | — | `DateTime` when job becomes available |

**Examples**

```elixir
# Immediate job
{:ok, job} = Kathikon.insert(MyWorker, %{"id" => "1"})

# Email queue, high priority
{:ok, job} =
  Kathikon.insert(EmailWorker, %{"to" => "a@b.com"},
    queue: :emails,
    priority: 5
  )

# Delayed job
{:ok, job} =
  Kathikon.insert(DigestWorker, %{},
    schedule_in: 3600
  )

# Fixed time
{:ok, job} =
  Kathikon.insert(ReportWorker, %{},
    schedule_at: ~U[2026-12-25 09:00:00Z]
  )
```

### `cancel/1`

```elixir
@spec cancel(String.t()) :: {:ok, Job.t()} | {:error, term()}
```

```elixir
{:ok, job} = Kathikon.cancel("abc123...")
# {:error, :executing}
# {:error, {:invalid_state, :completed}}
```

### `fetch/1`

```elixir
@spec fetch(String.t()) :: {:ok, Job.t()} | {:error, :not_found}
```

```elixir
{:ok, job} = Kathikon.fetch(job_id)
job.state
job.attempts
job.errors
```

### `all/0`

```elixir
@spec all() :: [Job.t()]
```

Returns every job in storage. Intended for tests and debugging.

```elixir
Kathikon.all()
|> Enum.count(&(&1.state == :completed))
```

### `start_queue/1`

```elixir
@spec start_queue(atom()) :: :ok
```

Ensures a dispatcher is running for the queue.

```elixir
:ok = Kathikon.start_queue(:imports)
```

---

## Kathikon.Job

Struct representing a durable job obligation.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String.t()` | Unique hex id |
| `queue` | `atom()` | Target queue |
| `worker` | `module()` | Worker module |
| `args` | `map()` | Arguments for `perform/1` |
| `state` | atom | Current lifecycle state |
| `priority` | `non_neg_integer()` | Claim ordering |
| `max_attempts` | `pos_integer()` | Retry ceiling |
| `attempts` | `non_neg_integer()` | Completed attempts |
| `scheduled_at` | `DateTime \| nil` | When scheduled job becomes due |
| `available_at` | `DateTime \| nil` | When job can be claimed |
| `inserted_at` | `DateTime \| nil` | Insert time |
| `started_at` | `DateTime \| nil` | Last claim time |
| `completed_at` | `DateTime \| nil` | Success or discard time |
| `cancelled_at` | `DateTime \| nil` | Cancel time |
| `errors` | `[map()]` | Failure history |

### States

`:scheduled` → `:available` → `:claimed` → `:running` → `:completed` | `:retryable` | `:dead` | `:cancelled`

### `build/3`

```elixir
@spec build(module(), map(), keyword()) :: t()
```

Low-level job construction. Prefer `Kathikon.insert/3`.

```elixir
job = Kathikon.Job.build(MyWorker, %{"x" => 1}, queue: :default, priority: 2)
```

### `claimable?/2`

```elixir
@spec claimable?(t(), DateTime.t()) :: boolean()
```

```elixir
Kathikon.Job.claimable?(job, DateTime.utc_now())
# true when state in [:available, :retryable] and available_at <= now
```

### `backoff_seconds/1`

```elixir
Kathikon.Job.backoff_seconds(2)  # 20
```

---

## Kathikon.Worker

Behaviour for job workers.

### Callback

```elixir
@callback perform(Kathikon.Job.t()) :: :ok | {:error, term()} | {:sleep, pos_integer()}
```

### Example

```elixir
defmodule MyApp.Workers.Webhook do
  use Kathikon.Worker

  @impl true
  def perform(%{args: %{"url" => url, "body" => body}}) do
    case MyApp.HTTP.post(url, body) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

---

## Kathikon.Config

Runtime configuration readers. Set values in `config :kathikon, ...`.

| Function | Returns |
|----------|---------|
| `queues/0` | Keyword of queue configs |
| `queue_names/0` | `[atom()]` |
| `queue_config/1` | Keyword for one queue |
| `concurrency/1` | Max tasks for queue |
| `poll_interval/0` | Dispatcher poll ms |
| `scheduler_interval/0` | Scheduler tick ms |
| `prune_interval/0` | Pruner tick ms |
| `retention_period/0` | Terminal job retention ms |
| `max_attempts/0` | Default retry limit |
| `mnesia_copies/0` | `:ram` or `:disc` |

```elixir
Kathikon.Config.concurrency(:emails)  # 5
```

---

## Kathikon.Storage

Facade over the configured storage backend. Used internally; embedders may call `setup/0`.

| Function | Description |
|----------|-------------|
| `setup/0` | Create Mnesia schema and tables |
| `clear_jobs!/0` | Delete all jobs (tests) |
| `reset!/0` | Drop and recreate tables (tests) |
| `insert/1`, `update/1`, `fetch/1`, `delete/1` | Job CRUD |
| `claim/2` | Atomic queue claim |
| `promote_scheduled/1` | Batch schedule promotion |
| `all/0` | List jobs |
| `backend/0`, `backend/1` | Get/set backend module |

```elixir
:ok = Kathikon.Storage.setup()
```

---

## Kathikon.Telemetry

### `attach_default_logger/0`

Attaches a logger handler for all Kathikon events.

```elixir
Kathikon.Telemetry.attach_default_logger()
```

### Events

See [Telemetry guide](../guides/telemetry-and-observability.md).

---

## Runtime processes

These modules are started by `Kathikon.Application`. You typically do not call them directly.

### Kathikon.Application

OTP application callback. Calls `Storage.setup/0` and starts the supervision tree.

### Kathikon.Queue

`DynamicSupervisor` for per-queue dispatchers.

| Function | Description |
|----------|-------------|
| `ensure_started/1` | Start dispatcher for queue |
| `start_configured/0` | Start all configured queues |

### Kathikon.Dispatcher

`GenServer` — polls Mnesia, claims jobs, spawns `Task` workers.

Registered as `{:dispatcher, queue}` in `Kathikon.Registry`.

`start_link/1` options: `:queue`, `:config`, `:poll_interval`, `:storage` (defaults to `Kathikon.Storage`).

### Kathikon.Scheduler.Promoter

`GenServer` — ticks on `scheduler_interval`, calls `storage.promote_scheduled/1`.

Registered as `Kathikon.Scheduler.Promoter` when started by the application.

`start_link/1` options: `:interval`, `:storage`, `:name` (`false` for unnamed test instances).

### Kathikon.Scheduler

Facade for scheduling APIs (`schedule/3`, `schedule_once/3`, etc.). Not a registered process.

### Kathikon.Pruner

`GenServer` — deletes terminal jobs past `retention_period`.

Registered as `Kathikon.Pruner` when started by the application.

`start_link/1` options: `:interval`, `:storage`, `:name` (`false` for unnamed test instances).

### Kathikon.Cron

Recurring cron schedules. Each match enqueues a durable job.

```elixir
Kathikon.Cron.insert(worker, args, cron: "0 9 * * *", queue: :email)
Kathikon.Cron.update(schedule_id, cron: "0 10 * * *")
Kathikon.Cron.fetch(schedule_id)
Kathikon.Cron.list()
Kathikon.Cron.cancel(schedule_id)
Kathikon.Cron.valid?(expression)
```

---

## Placeholders (not implemented)

### Kathikon.Lifeline

```elixir
Kathikon.Lifeline.start_link()
# {:error, :not_implemented}  — Phase 2
```

---

## Internal (extension points)

| Module | Role |
|--------|------|
| `Kathikon.Storage` | Storage behaviour and facade |
| `Kathikon.Storage.Mnesia` | Default Mnesia implementation |

Configure via `storage_backend: Kathikon.Storage.Mnesia`.
