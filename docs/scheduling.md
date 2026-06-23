# Scheduling

Kathikon separates **when** work is triggered from **how** it runs.

## One-time scheduling

```elixir
Kathikon.schedule(MyWorker, args, at: ~U[2026-01-01 09:00:00Z])
Kathikon.schedule(MyWorker, args, in: 3600)
```

Or via `Kathikon.insert/3` with `:schedule_at` / `:schedule_in`.

## Recurring cron

```elixir
{:ok, id} = Kathikon.Cron.insert(MyWorker, args, cron: "0 * * * *")
{:ok, schedule} = Kathikon.Cron.update(id, cron: "0 30 * * *")
:ok = Kathikon.Cron.cancel(id)
```

Equivalent via the scheduler facade:

```elixir
Kathikon.schedule(MyWorker, args, cron: "0 * * * *")
```

## Built-in scheduler

Default adapter: `Kathikon.Scheduler.BuiltIn`

- `at` / `in` create durable `:scheduled` jobs promoted by `Kathikon.Scheduler.Promoter`
- `cron` registers recurring specs in Mnesia, fired by `Kathikon.Scheduler.BuiltIn.Tick`

## Configuration

```elixir
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
config :kathikon, scheduler: Kathikon.Scheduler.BuiltIn, timezone: "Etc/UTC"
```

Quantum integration is optional — see `docs/quantum_adapter.md`.
