# Scheduling

Delay job execution with `schedule_in` or `schedule_at`. Scheduled jobs start in the `:scheduled` state until the scheduler promotes them to `:available`.

## schedule_in — relative delay

Run a job N seconds from now:

```elixir
{:ok, job} =
  Kathikon.insert(MyApp.Workers.SendDigest, %{"user_id" => "42"},
    schedule_in: 3600   # one hour
  )

job.state         # :scheduled
job.scheduled_at  # ~1 hour from insert time
```

```elixir
# config/config.exs
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :kathikon, timezone: "America/New_York"
```

Kathikon stores all timestamps in UTC. The configured timezone affects:

- Cron expressions and presets (`@daily` = local midnight)
- `schedule_at` when given as `NaiveDateTime` (wall clock in that zone)
- Scheduler `at:` option (same rules as `schedule_at`)

`:schedule_in` is duration-based and unaffected by timezone.

## schedule_at — absolute time

Run at a specific time in the configured timezone (or pass an explicit UTC `DateTime`):

```elixir
# Wall clock in config :kathikon, timezone (e.g. America/New_York)
{:ok, job} =
  Kathikon.insert(MyApp.Workers.SendReminder, %{"user_id" => "42"},
    schedule_at: ~N[2026-12-25 09:00:00]
  )

# Explicit UTC still works
{:ok, job} =
  Kathikon.insert(MyApp.Workers.SendReminder, %{"user_id" => "42"},
    schedule_at: ~U[2026-12-25 14:00:00Z]
  )
```

If `schedule_at` is **in the past**, the job is inserted as `:available` immediately.

## How promotion works

`Kathikon.Scheduler.Promoter` ticks every `scheduler_interval` ms (default `1000`). On each tick it runs `Storage.promote_scheduled/1`, which in a **single Mnesia transaction**:

1. Finds all `:scheduled` jobs where `scheduled_at <= now`
2. Sets `state: :available` and `available_at: now`
3. Returns the count promoted

Batch promotion prevents sibling scheduled jobs from becoming claimable one-by-one in priority order before their peers are ready.

## Inspecting scheduled jobs

```elixir
{:ok, job} = Kathikon.fetch(job_id)
job.state  # :scheduled until promotion

# After scheduler tick:
{:ok, job} = Kathikon.fetch(job_id)
job.state  # :available
```

## Scheduling + priority

```elixir
# VIP digest runs before standard digest when both become due together
Kathikon.insert(VipDigestWorker, %{}, schedule_in: 60, priority: 10, queue: :email)
Kathikon.insert(DigestWorker, %{}, schedule_in: 60, priority: 1, queue: :email)
```

## Cancelling scheduled jobs

Scheduled jobs can be cancelled before they run:

```elixir
{:ok, _} = Kathikon.cancel(job.id)
```

See [Cancellation](cancellation.md).

## Configuration

```elixir
config :kathikon, scheduler_interval: 1_000   # ms between promotion ticks
```

Lower values reduce scheduling latency; higher values reduce Mnesia load.

## Recurring cron

Register jobs that run on a cron schedule. Schedules are stored in Mnesia and
evaluated every `scheduler_interval` ms by `Kathikon.Scheduler.BuiltIn.Tick`.

```elixir
{:ok, id} =
  Kathikon.Cron.insert(MyApp.Workers.SendReminder, %{"user_id" => "42"},
    cron: "@daily",
    queue: :email
  )
```

Preset macros: `@hourly`, `@daily`, `@midnight`, `@weekly`, `@monthly`, `@yearly`, `@annually`.
All presets use the configured `timezone` (e.g. `@daily` = local midnight).

Each tick enqueues a durable Kathikon job when the expression matches.

### Update at runtime

Change the cron expression (or worker, args, queue) without restarting:

```elixir
{:ok, schedule} = Kathikon.Cron.update(id, cron: "0 10 * * *")
```

Updating `:cron` resets the last-fired timestamp so the new schedule can match
on the next tick.

### Cancel and inspect

```elixir
{:ok, schedule} = Kathikon.Cron.fetch(id)
{:ok, schedules} = Kathikon.Cron.list()
:ok = Kathikon.Cron.cancel(id)
```

Cron uses a minimal 5-field parser (`minute hour dom month dow`). For production
recurring schedules, consider `Kathikon.Scheduler.Quantum` — see `docs/quantum_adapter.md`.

## Not yet available

**Advanced cron** — ranges, lists, and per-schedule time zones are not supported by the built-in parser.
Use a single application timezone via `config :kathikon, timezone: ...`.

## Related

- [Module reference: Kathikon.Scheduler.Promoter](../reference/modules.md#kathikonschedulerpromoter)
- [Cancellation](cancellation.md)
