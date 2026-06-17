# Storage and embedding

Kathikon persists jobs in **Mnesia** via `Kathikon.Storage`, backed by `Kathikon.Backend.Storage.Mnesia`.

## Automatic startup

When Kathikon is a dependency, `Kathikon.Application` runs on boot:

1. `Kathikon.Storage.setup/0` — Mnesia schema + `:kathikon_jobs` / `:kathikon_queues` tables
2. Starts Registry, Queue supervisor, Scheduler, Pruner
3. `Kathikon.Queue.start_configured/0` — dispatchers for configured queues

No manual Mnesia setup is required in a standard Phoenix or Mix release.

## Manual embedding

If you start Kathikon outside its application (scripts, Livebook, tests):

```elixir
Application.put_env(:kathikon, :mnesia_copies, :ram)

{:ok, _} = Application.ensure_all_started(:kathikon)
# or, without full app:
:ok = Kathikon.Storage.setup()
```

## Livebook

Livebook nodes are named but lack a Mnesia disc directory. Use RAM copies:

```elixir
Mix.install(
  [{:kathikon, path: "..", env: :dev}],
  config: [kathikon: [mnesia_copies: :ram, poll_interval: 150, ...]]
)
```

See the [interactive demo](../../livebooks/kathikon_demo.livemd).

## Test helpers

```elixir
# Clear jobs between tests
:ok = Kathikon.Storage.clear_jobs!()

# Swap storage backend (Mox)
Kathikon.Storage.backend(Kathikon.Backend.Storage.Mock)
on_exit(fn -> Kathikon.Storage.backend(Kathikon.Backend.Storage.Mnesia) end)
```

`clear_jobs!/0` and `reset!/0` are intended for tests — not public production APIs.

## Storage facade

`Kathikon.Storage` delegates to a configurable backend:

| Function | Purpose |
|----------|---------|
| `setup/0` | Bootstrap schema and tables |
| `insert/1`, `update/1`, `fetch/1` | Job CRUD |
| `claim/2` | Atomic claim for a queue |
| `promote_scheduled/1` | Scheduler batch promotion |
| `prunable_jobs/1`, `delete/1` | Pruner support |
| `all/0` | List all jobs |
| `register_queue/2` | Persist queue metadata |

Application code should use `Kathikon.insert/3` rather than calling `Storage` directly.

## Backend plug-in

```elixir
config :kathikon, storage_backend: Kathikon.Backend.Storage.Mnesia
```

The behaviour is `Kathikon.Backend.Storage`. Phase 1 ships one implementation (`Kathikon.Backend.Storage.Mnesia`). Future phases add lease and cron backends under `Kathikon.Backend.*`.

## Tables

| Table | Contents |
|-------|----------|
| `:kathikon_jobs` | Job records (id, serialized `%Kathikon.Job{}`) |
| `:kathikon_queues` | Queue name + config keyword |

## Related

- [Configuration](configuration.md) — `mnesia_copies`, `storage_backend`
- [Module reference: Kathikon.Storage](../reference/modules.md#kathikonstorage)
