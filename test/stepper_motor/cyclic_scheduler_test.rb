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

  it "does not schedule a journey which is too far in the future" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 30.seconds)
    StepperMotor.scheduler = scheduler

    expect(scheduler).to receive(:schedule).with(instance_of(far_future_journey_class)).once.and_call_original
    _journey = far_future_journey_class.create!

    expect(scheduler).not_to receive(:schedule)
    scheduler.run_scheduling_cycle
  end

  it "only schedules journeys which are within its execution window" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 40.minutes)
    StepperMotor.scheduler = scheduler

    expect(scheduler).to receive(:schedule).with(instance_of(far_future_journey_class)).once.and_call_original
    journey = far_future_journey_class.create!

    expect(scheduler).to receive(:schedule).with(journey).and_call_original
    scheduler.run_scheduling_cycle
  end

  it "also schedules journeys which had to run in the past" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 10.seconds)
    StepperMotor.scheduler = scheduler

    expect(scheduler).to receive(:schedule).with(instance_of(far_future_journey_class)).once.and_call_original
    journey = far_future_journey_class.create!
    journey.update!(next_step_to_be_performed_at: 10.minutes.ago)

    expect(scheduler).to receive(:schedule).with(journey).and_call_original
    scheduler.run_scheduling_cycle
  end

  it "performs the scheduling job" do
    scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 10.seconds)
    StepperMotor.scheduler = scheduler
    job_class = StepperMotor::CyclicScheduler::RunSchedulingCycleJob
    expect(scheduler).to receive(:run_scheduling_cycle).and_call_original
    job_class.perform_now
  end

  it "does not perform the job if the configured scheduler is not the CyclicScheduler"
end
