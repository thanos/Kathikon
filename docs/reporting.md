# Reporting

`Kathikon.Report` provides simple scans over stored jobs.

```elixir
Kathikon.Report.queue_summary()
Kathikon.Report.job_counts()
Kathikon.Report.failure_summary()
Kathikon.Report.dead_letter_summary()
Kathikon.Report.throughput()
Kathikon.Report.latency()
```

## Performance

The initial implementation reads all jobs from Mnesia per call — fine for development and moderate volumes. For large deployments, export telemetry or add indexed aggregates in a future release.
