# Phase 1: Operations

> **Historical:** This document describes Kathikon v0.1.0. For v0.2.0 behaviour see the [documentation index](documentation.md) and [job lifecycle](job_lifecycle.md). State names changed (`:executing` → `:claimed`/`:running`); the scheduler process is `Kathikon.Scheduler.Promoter`.

Operational notes for running Kathikon v0.1.0 in development and early production.

## Deployment requirements

### Single-node development

```bash
mix deps.get
iex -S mix
```

On `nonode@nohost`, Mnesia uses `ram_copies`. Jobs do **not** survive BEAM restarts in this mode.

### Production node

Production nodes must:

1. Run as a **named, distributed Erlang node**
2. Start the `:mnesia` and `:kathikon` applications
3. Use `disc_copies` (automatic on named nodes)

Example:

```bash
NODE_NAME=kathikon@10.0.0.5 \
  elixir --name kathikon@10.0.0.5 \
         --cookie $RELEASE_COOKIE \
         -S mix run --no-halt
```

## Configuration checklist

```elixir
config :kathikon,
  queues: [
    default: [concurrency: 20],
    emails: [concurrency: 5],
    webhooks: [concurrency: 10]
  ],
  poll_interval: 200,
  scheduler_interval: 1_000,
  prune_interval: 60_000,
  retention_period: :timer.hours(24 * 7),
  max_attempts: 20
```

| Setting | Operational guidance |
|---------|---------------------|
| `concurrency` | Start conservative; increase while monitoring BEAM schedulers and memory |
| `poll_interval` | Lower = lower latency, higher CPU. 100–500ms is typical |
| `retention_period` | Size for debugging needs, not analytics. Export telemetry for long-term history |
| `max_attempts` | Tune per worker via `insert` opts for critical vs. best-effort work |

## Telemetry and monitoring

Attach handlers to `[:kathikon, :job, :stop]` and `[:kathikon, :job, :discard]` for SLI tracking:

- Job throughput (jobs/min per queue)
- Error rate (`:discard` / total)
- Execution duration (`measurements.duration`)

Recommended tags in metadata: `queue`, `worker`, `attempt`.

### Default logger

```elixir
# config/dev.exs
config :kathikon, attach_logger: true
```

Or explicitly in application startup:

```elixir
Kathikon.Telemetry.attach_default_logger()
```

## Inspecting jobs

```elixir
# All jobs (use cautiously in production)
Kathikon.all()

# Single job
Kathikon.fetch("job_id")

# Filter in IEx (v0.1 used :executing; v0.2 uses :claimed and :running)
Kathikon.all() |> Enum.filter(&(&1.state in [:claimed, :running]))
```

## Common operational scenarios

### Stuck jobs in `:executing` (v0.1) / `:claimed` or `:running` (v0.2)

**Symptom:** Jobs remain in a running state after worker crash.

**Phase 1 limitation:** No automatic recovery yet.

**Mitigation:** Manually update or delete stuck jobs in IEx. Phase 2 lifeline will automate this.

```elixir
{:ok, job} = Kathikon.fetch("id")
Kathikon.Storage.update(%{job | state: :retryable, available_at: DateTime.utc_now()})
```

### Mnesia table growth

**Symptom:** Growing memory, slow claims.

**Checks:**

1. Is the pruner running? (`Process.whereis(Kathikon.Pruner)`)
2. Is `retention_period` too large?
3. Are jobs completing? Check `:discarded` and `:completed` counts.

**Mitigation:** Lower retention, manually prune, reduce job volume.

### Queue backlog

**Symptom:** Jobs sit in `:available` or `:scheduled`.

**Checks:**

1. Dispatcher alive for that queue?
2. `concurrency` saturated? (`:sys.get_state` on dispatcher)
3. Scheduler ticking for `:scheduled` jobs?

**Mitigation:** Increase concurrency, add dispatcher nodes (Phase 2), or scale horizontally.

## Production considerations

### Durability

| Environment | Durability |
|-------------|------------|
| `nonode@nohost` | None across restarts |
| Named node + `disc_copies` | Survives process restart |
| Multi-node cluster | Requires Phase 2 coordination |

### Capacity planning

Phase 1 claim is O(n) over all jobs. Plan for:

- **< 100k active jobs** per cluster for comfortable single-node performance
- Aggressive pruning of terminal states
- Separate queues for bursty vs. steady workloads

### Security

- Protect Erlang distribution cookie
- Do not expose Erlang ports to the public internet
- Worker modules execute arbitrary application code — validate args at insert time in your app layer

### Upgrades

Rolling upgrades across a cluster require Mnesia schema compatibility. Phase 1 schema is minimal. Before upgrading:

1. Drain or pause queues (Phase 4)
2. Verify table schema backward compatibility
3. Roll one node at a time

### Backup

Mnesia supports backup via `:mnesia.backup/2`. For Phase 1:

- Back up before schema changes
- Do not rely on Mnesia as the only audit trail — export telemetry to your observability stack

## Health checks

Minimal health check for a release:

```elixir
def healthy? do
  :mnesia.system_info(:is_running) == :yes and
    Process.whereis(Kathikon.Scheduler.Promoter) != nil and
    Process.whereis(Kathikon.Pruner) != nil
end
```

## Runbook summary

| Alert | Likely cause | Action |
|-------|--------------|--------|
| High `:running` / `:claimed` count | Worker crashes | Manual recovery; wait for Phase 2 lifeline |
| Growing job table | Pruner misconfigured | Check retention, restart pruner |
| No job progress | Dispatcher down | Restart app, check queue config |
| High discard rate | Worker logic errors | Fix worker, inspect `job.errors` |
