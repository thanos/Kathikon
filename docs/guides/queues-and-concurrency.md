# Queues and concurrency

Each queue has its own **dispatcher** process that claims jobs from Mnesia and runs them with bounded concurrency.

## Configuring queues

```elixir
# config/config.exs
config :kathikon,
  queues: [
    default: [concurrency: 10],
    emails: [concurrency: 5],
    thumbnails: [concurrency: 2]
  ]
```

On application start, `Kathikon.Queue.start_configured/0` starts a dispatcher for each configured queue.

## Enqueueing to a specific queue

```elixir
{:ok, job} =
  Kathikon.insert(MyApp.Workers.SendEmail, %{"to" => "a@b.com"},
    queue: :emails
  )
```

`Kathikon.insert/3` calls `Kathikon.Queue.ensure_started/1`, so dispatchers for ad-hoc queues are started on first insert even if not listed in config (they get default concurrency `10`).

## Starting a queue manually

```elixir
:ok = Kathikon.start_queue(:reports)
```

Useful when adding queues at runtime before Phase 3 dynamic queue management.

## How concurrency works

Each dispatcher:

1. Polls Mnesia every `poll_interval` ms (default `200`)
2. Atomically **claims** up to `concurrency - running` jobs
3. Spawns a `Task` per job to call `worker.perform/1`
4. Updates job state when the task finishes

```elixir
# Two thumbnail jobs can run in parallel; a third waits
config :kathikon,
  queues: [thumbnails: [concurrency: 2]]
```

## Claim ordering

When multiple jobs are available on the same queue:

1. Higher `priority` first
2. Earlier `available_at` as tiebreaker

```elixir
Kathikon.insert(Worker, %{}, priority: 10)  # claimed before priority: 1
```

See [Scheduling](scheduling.md) for priority with scheduled jobs.

## Isolation between queues

Queues are **failure domains**:

- A crashed dispatcher restarts via `DynamicSupervisor` without affecting other queues
- Slow work on `:thumbnails` does not block `:emails`
- Each queue has independent concurrency limits

## Registry lookup

Dispatchers register as `{:dispatcher, queue_name}` in `Kathikon.Registry`:

```elixir
GenServer.whereis({:via, Registry, {Kathikon.Registry, {:dispatcher, :emails}}})
```

## Related

- `Kathikon.Config.concurrency/1`, `queue_names/0`
- [Module reference: Kathikon.Queue](../reference/modules.md#kathikonqueue)
- [Module reference: Kathikon.Dispatcher](../reference/modules.md#kathikondispatcher)
