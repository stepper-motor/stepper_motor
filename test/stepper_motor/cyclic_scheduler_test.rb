# frozen_string_literal: true

require "test_helper"

class CyclicSchedulerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @previous_scheduler = StepperMotor.scheduler
    StepperMotor::Journey.delete_all
  end

  teardown do
    StepperMotor.scheduler = @previous_scheduler
  end

  def far_future_journey_class
    @klass ||= create_journey_subclass do
      step :do_thing, wait: 40.minutes do
        raise "We do not test this so it should never run"
      end
    end
  end

  test "does not schedule a journey which is too far in the future" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 30.seconds)
    StepperMotor.scheduler = scheduler

    assert_no_enqueued_jobs do
      far_future_journey_class.create!
    end

    assert_no_enqueued_jobs do
      scheduler.run_scheduling_cycle
    end
  end

  test "for a job inside the current scheduling cycle, enqueues the job immediately" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 40.minutes)
    StepperMotor.scheduler = scheduler

    assert_enqueued_jobs 1, only: StepperMotor::PerformStepJobV2 do
      far_future_journey_class.create!
    end
  end

  test "also schedules journeys which had to run in the past" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 10.seconds)
    StepperMotor.scheduler = scheduler

    journey = nil
    assert_no_enqueued_jobs do
      journey = far_future_journey_class.create!
    end
    journey.update!(next_step_to_be_performed_at: 10.minutes.ago)

    assert_enqueued_jobs 1, only: StepperMotor::PerformStepJobV2 do
      scheduler.run_scheduling_cycle
    end
  end

  test "performs the scheduling job without raising exceptions even if the cycling scheduler is not the one active" do
    StepperMotor.scheduler = StepperMotor::ForwardScheduler.new
    assert_nothing_raised do
      StepperMotor::CyclicScheduler::RunSchedulingCycleJob.new.perform
    end
  end

  test "performs the scheduling job without raising exceptions if the cycling scheduler is the active" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 10.seconds)
    StepperMotor.scheduler = scheduler

    assert_nothing_raised do
      StepperMotor::CyclicScheduler::RunSchedulingCycleJob.new.perform
    end
  end
end
