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

## schedule_at — absolute time

Run at a specific `DateTime` (UTC):

```elixir
send_at = DateTime.utc_now() |> DateTime.add(1, :day)

{:ok, job} =
  Kathikon.insert(MyApp.Workers.SendReminder, %{"user_id" => "42"},
    schedule_at: send_at
  )
```

If `schedule_at` is **in the past**, the job is inserted as `:available` immediately.

## How promotion works

`Kathikon.Scheduler` ticks every `scheduler_interval` ms (default `1000`). On each tick it runs `Storage.promote_scheduled/1`, which in a **single Mnesia transaction**:

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

## Not yet available

**Cron** (`Kathikon.Cron`) — recurring schedules — is planned for Phase 3. Until then, re-enqueue from `perform/1` or use an external scheduler to call `Kathikon.insert/3`.

## Related

- [Module reference: Kathikon.Scheduler](../reference/modules.md#kathikonscheduler)
- [Cancellation](cancellation.md)
