defmodule Kathikon.TelemetryTest do
  use ExUnit.Case, async: true

  alias Kathikon.Telemetry

  test "event/3 executes telemetry" do
    test_pid = self()
    id = "kathikon-test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      id,
      [:kathikon, :job, :insert],
      fn event, measurements, metadata, pid ->
        send(pid, {:event, event, measurements, metadata})
      end,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(id) end)

    Telemetry.event([:job, :insert], %{count: 1}, %{queue: :default, job_id: "abc"})

    assert_receive {:event, [:kathikon, :job, :insert], %{count: 1},
                    %{queue: :default, job_id: "abc"}}
  end

  test "attach_default_logger logs events" do
    :telemetry.detach("kathikon-default-logger")

    assert :ok = Telemetry.attach_default_logger()
    assert {:error, :already_exists} = Telemetry.attach_default_logger()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        Telemetry.event([:job, :stop], %{duration: 10}, %{
          queue: :default,
          job_id: "abc"
        })
      end)

    assert log =~ "kathikon.job.stop"
    assert log =~ "queue=default"
    assert log =~ "job=abc"
  end
end
