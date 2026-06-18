# Telemetry and observability

Kathikon emits standard [`:telemetry`](https://hexdocs.pm/telemetry) events for every significant lifecycle transition.

## Event prefix

All events start with `[:kathikon, ...]`.

## Job events

| Event | When | Measurements | Metadata |
|-------|------|--------------|----------|
| `[:kathikon, :job, :insert]` | Job enqueued | `%{}` | `queue`, `job_id`, `worker`, `state` |
| `[:kathikon, :job, :start]` | `perform/1` begins | `%{}` | `queue`, `job_id`, `worker`, `attempt` |
| `[:kathikon, :job, :stop]` | Success | `%{duration: μs}` | `queue`, `job_id`, `worker`, `attempt`, `result: :ok` |
| `[:kathikon, :job, :sleep]` | Deferred (`{:sleep, seconds}`) | `%{duration: μs}` | `queue`, `job_id`, `worker`, `attempt`, `result: :sleep`, `seconds` |
| `[:kathikon, :job, :retry]` | Failure, will retry | `%{duration: μs}` | `queue`, `job_id`, `reason`, `result: :retry`, `backoff`, `attempt` |
| `[:kathikon, :job, :discard]` | Max attempts exceeded | `%{duration: μs}` | `queue`, `job_id`, `reason`, `result: :discarded`, `attempt` |
| `[:kathikon, :job, :cancel]` | User cancelled | `%{}` | `queue`, `job_id` |
| `[:kathikon, :job, :prune]` | Terminal job deleted | `%{}` | `queue`, `job_id`, `state` |

`duration` is native time units (microseconds on most platforms).

## Runtime events

| Event | When | Measurements | Metadata |
|-------|------|--------------|----------|
| `[:kathikon, :scheduler, :tick]` | Scheduler promoted jobs | `%{promoted: count}` | `%{}` |
| `[:kathikon, :pruner, :tick]` | Pruner deleted jobs | `%{pruned: count}` | `%{}` |
| `[:kathikon, :dispatcher, :poll]` | Job claimed on poll | `%{count: 1}` | `queue`, `job_id` |

## Default logger

```elixir
# config/dev.exs or IEx
Kathikon.Telemetry.attach_default_logger()
```

Logs lines like:

```
[kathikon] kathikon.job.stop queue=default job=abc... %{duration: 45000} %{result: :ok, ...}
```

## Custom handler

```elixir
:telemetry.attach(
  "my-app-kathikon",
  [[:kathikon, :job, :stop], [:kathikon, :job, :discard]],
  fn event, measurements, metadata, _config ->
    MyApp.Metrics.increment("kathikon.job.#{event |> List.last()}")
    MyApp.Metrics.timing("kathikon.job.duration", measurements[:duration])
  end,
  nil
)
```

## Handler in tests

```elixir
test "emits insert telemetry" do
  ref = :telemetry_test.attach_event_handlers(self(), [[:kathikon, :job, :insert]])

  {:ok, _} = Kathikon.insert(MyWorker, %{})

  assert_receive {:event, [:kathikon, :job, :insert], %{}, metadata}
  assert metadata.queue == :default
end
```

## Inspection API

For debugging and tests (not a production dashboard):

```elixir
Kathikon.all()                    # all jobs in Mnesia
Kathikon.fetch(job_id)            # single job
```

Phase 6 will add structured observability APIs.

## Related

- `Kathikon.Telemetry` module
- [Module reference](../reference/modules.md#kathikontelemetry)
