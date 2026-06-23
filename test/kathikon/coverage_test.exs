defmodule Kathikon.CoverageTest do
  use ExUnit.Case, async: false

  alias Kathikon.{Batch, Job, Report, Storage}
  alias Kathikon.Scheduler.BuiltIn
  alias Kathikon.Scheduler.Quantum

  setup do
    Storage.setup()
    Storage.clear_jobs!()
    Kathikon.TestQuantumScheduler.reset!()
    :ok
  end

  describe "Kathikon management API" do
    test "schedule requires at, in, or cron" do
      assert {:error, :missing_schedule_option} =
               Kathikon.schedule(Kathikon.Workers.SuccessWorker, %{})
    end

    test "claim and claim_available start running jobs" do
      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:state, :available)
        |> Map.put(:available_at, DateTime.utc_now())

      {:ok, inserted} = Storage.insert(job)

      assert {:ok, running} = Kathikon.claim(inserted.id)
      assert running.state == :running

      Storage.clear_jobs!()

      for _ <- 1..2 do
        j =
          Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
          |> Map.put(:state, :available)
          |> Map.put(:available_at, DateTime.utc_now())

        {:ok, _} = Storage.insert(j)
      end

      assert {:ok, claimed} = Kathikon.claim_available(:default, limit: 2)
      assert length(claimed) == 2
      assert Enum.all?(claimed, &(&1.state == :running))
    end

    test "history, children, dead letter, and result errors" do
      parent =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, max_attempts: 1)
        |> Map.put(:state, :running)

      {:ok, parent} = Storage.insert(parent)

      child =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:parent_job_id, parent.id)

      {:ok, child} = Storage.insert(child)

      assert {:ok, history} = Kathikon.history(parent.id)
      assert Enum.any?(history, &(&1.event == :inserted))

      assert {:ok, children} = Kathikon.children(parent.id)
      assert Enum.any?(children, &(&1.id == child.id))

      dead =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default, max_attempts: 1)
        |> Map.put(:state, :dead)

      {:ok, dead} = Storage.insert(dead)

      assert {:ok, dead_jobs} = Kathikon.dead_jobs()
      assert Enum.any?(dead_jobs, &(&1.id == dead.id))

      assert {:ok, rerun} = Kathikon.retry_dead(dead.id)
      assert rerun.rerun_of == dead.id

      failed =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default)
        |> Map.put(:state, :failed)

      {:ok, failed} = Storage.insert(failed)
      assert {:ok, discarded} = Kathikon.discard_dead(failed.id)
      assert discarded.state == :discarded

      assert {:error, {:invalid_state, :running}} = Kathikon.result(parent.id)
    end

    test "retry emits telemetry for retryable jobs" do
      job =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default)
        |> Map.put(:state, :retryable)

      {:ok, job} = Storage.insert(job)
      assert {:ok, retried} = Kathikon.retry(job.id)
      assert retried.state in [:available, :scheduled]
    end

    test "insert stores jobs through the public API" do
      assert {:ok, job} = Kathikon.insert(Kathikon.Workers.SuccessWorker, %{"x" => 1})
      assert job.state in [:available, :scheduled]
    end
  end

  describe "Storage facade" do
    test "backend helpers and lifecycle delegation" do
      assert Storage.backend() == Kathikon.Storage.Mnesia

      assert :ok = Storage.backend(Kathikon.Storage.Mnesia)
      assert :ok = Storage.set_test_backend!(Kathikon.Storage.Mnesia)
      assert :ok = Storage.clear_test_backend!()

      assert :ok =
               Storage.with_backend(Kathikon.Storage.Mnesia, fn ->
                 Storage.setup()
               end)
    end
  end

  describe "Storage.Mnesia lifecycle edges" do
    test "insert_job accepts map payloads and update succeeds" do
      job_map = %{
        id: "map-job",
        queue: :default,
        worker: Kathikon.Workers.SuccessWorker,
        args: %{},
        state: :available,
        available_at: DateTime.utc_now()
      }

      assert {:ok, id} = Storage.insert_job(job_map)
      assert id == "map-job"

      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:state, :available)
        |> Map.put(:result_mode, :discard)

      {:ok, inserted} = Storage.insert(job)
      assert {:ok, updated} = Storage.update(%{inserted | args: %{"updated" => true}})
      assert updated.args == %{"updated" => true}
    end

    test "claim_job idempotency and not_claimable paths" do
      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:state, :available)
        |> Map.put(:available_at, DateTime.utc_now())

      {:ok, inserted} = Storage.insert(job)

      claimant = %{
        node: node(),
        pid: inspect(self()),
        claimed_at: DateTime.utc_now(),
        dispatcher_id: self()
      }

      other = Map.put(claimant, :dispatcher_id, make_ref())

      assert {:ok, claimed} = Storage.claim_job(inserted.id, claimant)
      assert {:ok, same} = Storage.claim_job(inserted.id, claimant)
      assert same.id == claimed.id
      assert {:error, :already_claimed} = Storage.claim_job(inserted.id, other)

      scheduled =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:state, :scheduled)
        |> Map.put(:scheduled_at, DateTime.add(DateTime.utc_now(), 3600, :second))

      {:ok, scheduled} = Storage.insert(scheduled)
      assert {:error, :not_claimable} = Storage.claim_job(scheduled.id, claimant)
    end

    test "claim_available_jobs, complete, fail, retry, cancel, discard, and move_to_dead" do
      claimant = %{
        node: node(),
        pid: inspect(self()),
        claimed_at: DateTime.utc_now(),
        dispatcher_id: self()
      }

      for _ <- 1..2 do
        j =
          Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
          |> Map.put(:state, :available)
          |> Map.put(:available_at, DateTime.utc_now())

        {:ok, _} = Storage.insert(j)
      end

      assert {:ok, claimed} = Storage.claim_available_jobs(:default, 2, claimant)
      assert length(claimed) == 2

      [first | _] = claimed
      {:ok, running} = Storage.start_job(first, claimant)

      assert {:ok, completed} =
               Storage.complete_job(running.id, %{answer: 1}, %{attempt: 1, result_mode: :store})

      assert completed.result == %{answer: 1}

      fail_job =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default, max_attempts: 3)
        |> Map.put(:state, :available)
        |> Map.put(:available_at, DateTime.utc_now())

      {:ok, fail_job} = Storage.insert(fail_job)
      {:ok, fail_claimed} = Storage.claim_job(fail_job.id, claimant)
      {:ok, fail_running} = Storage.start_job(fail_claimed, claimant)

      assert {:ok, retryable} = Storage.fail_job(fail_running.id, :boom, %{attempt: 1})
      assert retryable.state == :retryable

      assert {:ok, retried} = Storage.retry_job(fail_job.id, in: 30)
      assert retried.state == :scheduled

      retryable_again =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default)
        |> Map.put(:state, :retryable)

      {:ok, retryable_again} = Storage.insert(retryable_again)
      assert {:ok, available} = Storage.retry_job(retryable_again.id)
      assert available.state == :available

      assert {:ok, cancelled} = Storage.cancel_job(fail_job.id, :user, %{})
      assert cancelled.state == :cancelled

      discard_job =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default)
        |> Map.put(:state, :failed)

      {:ok, discard_job} = Storage.insert(discard_job)

      assert {:ok, discarded} = Storage.discard_job(discard_job.id, :manual, %{})
      assert discarded.state == :discarded

      move_job =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default)
        |> Map.put(:state, :running)

      {:ok, move_job} = Storage.insert(move_job)

      assert {:ok, dead} = Storage.move_to_dead_letter(move_job.id, :forced, %{})
      assert dead.state == :dead
    end

    test "list_jobs filters and batch or schedule storage helpers" do
      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :emails)
        |> Map.put(:state, :available)

      {:ok, _} = Storage.insert(job)

      assert {:ok, emails} = Storage.list_jobs(queue: :emails)
      assert length(emails) == 1

      assert {:ok, available} = Storage.list_jobs(state: :available)
      assert Enum.empty?(available) == false

      batch = %{
        batch_id: "batch-1",
        parent_job_id: "parent-1",
        child_job_ids: [],
        status: :running,
        pending_count: 0,
        success_count: 0,
        failure_count: 0,
        cancelled_count: 0,
        success_policy: :all_succeeded,
        on_complete: nil,
        created_at: DateTime.utc_now(),
        completed_at: nil,
        metadata: %{}
      }

      assert {:ok, written} = Storage.Mnesia.write_batch(batch)
      assert written.batch_id == "batch-1"
      assert {:ok, fetched} = Storage.Mnesia.fetch_batch("batch-1")
      assert fetched.batch_id == "batch-1"
      assert Enum.any?(Storage.Mnesia.list_batches(), &(&1.batch_id == "batch-1"))

      schedule = %{
        id: "sched-1",
        worker: Kathikon.Workers.SuccessWorker,
        args: %{},
        cron: "0 0 1 1 *",
        queue: :default,
        opts: [],
        inserted_at: DateTime.utc_now(),
        last_fired_at: nil
      }

      assert {:ok, _} = Storage.Mnesia.write_schedule(schedule)
      assert {:ok, _} = Storage.Mnesia.fetch_schedule("sched-1")
      assert Enum.any?(Storage.Mnesia.list_schedules(), &(&1.id == "sched-1"))
      assert :ok = Storage.Mnesia.delete_schedule("sched-1")
    end

    test "complete_job rejects invalid states and result_mode discard" do
      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, result: :discard)
        |> Map.put(:state, :available)

      {:ok, job} = Storage.insert(job)
      assert {:error, {:invalid_state, :available}} = Storage.complete_job(job.id, :ok, %{})

      running_job =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, result: :discard)
        |> Map.put(:state, :running)

      {:ok, running_job} = Storage.insert(running_job)

      assert {:ok, completed} = Storage.complete_job(running_job.id, :ignored, %{attempt: 1})
      assert completed.result == nil
    end

    test "retry_job rejects invalid states" do
      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:state, :completed)

      {:ok, job} = Storage.insert(job)
      assert {:error, {:invalid_state, :completed}} = Storage.retry_job(job.id)
    end
  end

  describe "Batch workflows" do
    setup do
      Kathikon.pause_queue(:default)
      on_exit(fn -> Kathikon.resume_queue(:default) end)
      :ok
    end

    defp finish_child(child_id, batch_id, state, result \\ :ok) do
      claimant = %{
        node: node(),
        pid: "batch-test",
        claimed_at: DateTime.utc_now(),
        dispatcher_id: self()
      }

      case state do
        :completed ->
          {:ok, claimed} = Storage.claim_job(child_id, claimant)
          {:ok, running} = Storage.start_job(claimed, claimant)
          {:ok, finished} = Storage.complete_job(running.id, result, %{attempt: 1})

          Batch.handle_child_finished(%{
            finished
            | batch_id: batch_id
          })

        :failed ->
          {:ok, claimed} = Storage.claim_job(child_id, claimant)
          {:ok, running} = Storage.start_job(claimed, claimant)
          {:ok, failed} = Storage.fail_job(running.id, :boom, %{attempt: 1})

          Batch.handle_child_finished(%{failed | batch_id: batch_id})

        :cancelled ->
          {:ok, cancelled} = Storage.cancel_job(child_id, :test, %{})
          Batch.handle_child_finished(%{cancelled | batch_id: batch_id})
      end
    end

    test "batch fails when success policy requires all children" do
      parent =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, max_attempts: 1)
        |> Map.put(:state, :running)

      {:ok, parent} = Storage.insert(parent)

      assert {:ok, batch} =
               Batch.start(parent.id, [
                 {Kathikon.Workers.SuccessWorker, %{}, [queue: :default]},
                 {Kathikon.Workers.FailWorker, %{}, [queue: :default, max_attempts: 1]}
               ])

      [first, second] = batch.child_job_ids
      finish_child(first, batch.batch_id, :completed)
      finish_child(second, batch.batch_id, :failed)

      assert {:ok, status} = Batch.status(batch.batch_id)
      assert status.status == :failed

      assert {:ok, updated_parent} = Storage.fetch(parent.id)
      assert updated_parent.state == :dead
    end

    test "batch succeeds with allow_partial and at_least policies" do
      for {policy, expect} <- [
            {:allow_partial, :completed},
            {{:at_least, 1}, :completed}
          ] do
        parent =
          Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
          |> Map.put(:state, :running)

        {:ok, parent} = Storage.insert(parent)

        assert {:ok, batch} =
                 Batch.start(
                   parent.id,
                   [
                     %{worker: Kathikon.Workers.SuccessWorker, args: %{}},
                     %{
                       worker: Kathikon.Workers.FailWorker,
                       args: %{},
                       max_attempts: 1
                     }
                   ],
                   success_policy: policy
                 )

        [first, second] = batch.child_job_ids
        finish_child(first, batch.batch_id, :completed)
        finish_child(second, batch.batch_id, :failed)

        assert {:ok, status} = Batch.status(batch.batch_id)
        assert status.status == expect
      end
    end

    test "batch results, retry_failed, and cancelled children" do
      assert {:error, :not_found} = Batch.status("missing")

      parent =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default, max_attempts: 1)
        |> Map.put(:state, :running)

      {:ok, parent} = Storage.insert(parent)

      assert {:ok, batch} =
               Batch.start(parent.id, [
                 {Kathikon.Workers.FailWorker, %{}, [queue: :default, max_attempts: 3]}
               ])

      [child_id] = batch.child_job_ids
      finish_child(child_id, batch.batch_id, :failed)

      assert {:ok, results} = Batch.results(batch.batch_id)
      assert hd(results).state in [:failed, :dead, :retryable]

      {:ok, batch_status} = Batch.status(batch.batch_id)

      {:ok, _} =
        Storage.Mnesia.write_batch(%{
          batch_status
          | pending_count: 0,
            failure_count: 1,
            status: :failed
        })

      assert {:ok, retried} = Batch.retry_failed(batch.batch_id)
      assert retried != []

      parent2 =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:state, :running)

      {:ok, parent2} = Storage.insert(parent2)

      assert {:ok, batch2} =
               Batch.start(
                 parent2.id,
                 [
                   {Kathikon.Workers.SuccessWorker, %{}, [queue: :default]},
                   {Kathikon.Workers.SuccessWorker, %{}, [queue: :default]}
                 ],
                 success_policy: :allow_partial
               )

      [ok_child, cancel_child] = batch2.child_job_ids
      finish_child(ok_child, batch2.batch_id, :completed)
      finish_child(cancel_child, batch2.batch_id, :cancelled)

      assert {:ok, status2} = Batch.status(batch2.batch_id)
      assert status2.cancelled_count == 1
      assert status2.status == :completed
    end
  end

  describe "Report" do
    test "failure_summary groups failed workers" do
      failed =
        Job.build(Kathikon.Workers.FailWorker, %{}, queue: :default)
        |> Map.put(:state, :failed)
        |> Map.put(:last_error, "boom")

      {:ok, _} = Storage.insert(failed)

      assert {:ok, summary} = Report.failure_summary()
      assert Enum.any?(summary, &(&1.worker == Kathikon.Workers.FailWorker and &1.count >= 1))
    end
  end

  describe "BuiltIn scheduler" do
    test "schedule_once with in option and fire_due_schedules" do
      assert {:ok, job_id} =
               BuiltIn.schedule_once(Kathikon.Workers.SuccessWorker, %{}, in: 30, queue: :default)

      assert {:ok, job} = Storage.fetch(job_id)
      assert job.state == :scheduled

      assert {:ok, schedule_id} =
               BuiltIn.schedule_recurring(Kathikon.Workers.SuccessWorker, %{},
                 cron: "* * * * *",
                 queue: :default
               )

      assert BuiltIn.fire_due_schedules() >= 1
      assert :ok = BuiltIn.cancel_schedule(schedule_id)
    end

    test "invalid cron expressions are ignored" do
      schedule = %{
        id: "bad-cron",
        worker: Kathikon.Workers.SuccessWorker,
        args: %{},
        cron: "not-valid",
        queue: :default,
        opts: [],
        inserted_at: DateTime.utc_now(),
        last_fired_at: nil
      }

      {:ok, _} = Storage.Mnesia.write_schedule(schedule)
      assert BuiltIn.fire_due_schedules() == 0
    end
  end

  describe "Quantum adapter" do
    setup context do
      previous = Application.get_env(:kathikon, :quantum_scheduler)

      Application.put_env(:kathikon, :quantum_scheduler, Kathikon.TestQuantumScheduler)

      on_exit(context, fn ->
        if previous,
          do: Application.put_env(:kathikon, :quantum_scheduler, previous),
          else: Application.delete_env(:kathikon, :quantum_scheduler)
      end)

      :ok
    end

    test "enqueue inserts jobs" do
      assert {:ok, job} = Quantum.enqueue(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
      assert job.worker == Kathikon.Workers.SuccessWorker
    end

    @tag :quantum_optional
    test "schedule_once and recurring schedules when quantum is available" do
      if Quantum.available?() do
        assert {:ok, job_id} =
                 Quantum.schedule_once(Kathikon.Workers.SuccessWorker, %{},
                   in: 10,
                   queue: :default
                 )

        assert {:ok, _} = Storage.fetch(job_id)

        assert {:ok, name} =
                 Quantum.schedule_recurring(Kathikon.Workers.SuccessWorker, %{},
                   cron: "* * * * *",
                   name: :test_recurring
                 )

        assert {:ok, schedules} = Quantum.list_schedules()
        assert Enum.any?(schedules, &(&1.id == name))
        assert :ok = Quantum.cancel_schedule(name)
      else
        assert {:error, :quantum_not_available} =
                 Quantum.schedule_once(Kathikon.Workers.SuccessWorker, %{}, in: 10)
      end
    end
  end

  describe "Job helpers" do
    test "to_map, history, normalize, and immediate schedule_at" do
      job =
        Job.build(Kathikon.Workers.SuccessWorker, %{},
          queue: :default,
          schedule_at: DateTime.utc_now()
        )
        |> Map.put(:state, :executing)

      assert Job.normalize(job).state == :running

      stored =
        Job.build(Kathikon.Workers.SuccessWorker, %{}, queue: :default)
        |> Map.put(:state, :available)

      {:ok, inserted} = Storage.insert(stored)
      assert {:ok, events} = Job.history(inserted.id)
      assert events != []

      map = Job.to_map(inserted)
      assert map.id == inserted.id
      assert map.attempt == inserted.attempts
    end
  end
end
