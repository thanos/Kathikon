# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-06-23

### Added

- `Kathikon.Dashboard` — operations facade for queue summaries, paginated job lists, job drill-down, bulk cancel/retry/rerun/discard/purge, and `actions_for_state/1` for UIs.
- `Kathikon.Dashboard.RPC` — whitelisted remote calls over Erlang distribution.
- `mix kathikon.ops` — terminal CLI for inspect and control (`summary`, `jobs`, `show`, `pause`, `resume`, `cancel`, `retry`, `rerun`, `purge`, `prune`).
- Public `@doc` for `Kathikon.pause_queue/1`, `resume_queue/1`, and `queue_status/1`.
- Dashboard and ops coverage in `test/kathikon/dashboard_test.exs`.

### Fixed

- `Kathikon.Dashboard.RPC.call/4` no longer double-wraps `{:ok, result}` tuples from remote nodes (fixes `mix kathikon.ops --node … summary`).

### Documentation

- Management API guide expanded with Dashboard and remote ops examples.
- Module reference grouping includes `Kathikon.Dashboard` in ExDoc.

## [0.2.0] - 2026-06-23

First feature release after Phase 1. Storage behaviour, formal job state machine, cron scheduling, timezone support, batches, reporting, management APIs, and expanded test coverage. See the [v0.2.0 release on GitHub](https://github.com/thanos/kathikon/releases/tag/v0.2.0).
