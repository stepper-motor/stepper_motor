# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "StepperMotor::ForwardScheduler" do
  include ActiveJob::TestHelper

  before do
    @previous_scheduler = StepperMotor.scheduler
    StepperMotor::Journey.delete_all
  end

  after do
    StepperMotor.scheduler = @previous_scheduler
  end

  def far_future_journey_class
    @klass ||= create_journey_subclass do
      step :do_thing, wait: 40.minutes do
        raise "We do not test this so it should never run"
      end
    end
  end

  it "schedules a journey 40 minutes ahead" do
    scheduler = StepperMotor::ForwardScheduler.new
    StepperMotor.scheduler = scheduler

    expect(scheduler).to receive(:schedule).with(instance_of(far_future_journey_class)).once.and_call_original
    _journey = far_future_journey_class.create!

    expect(enqueued_jobs.size).to eq(1)
    job = enqueued_jobs.first

    expect(job["job_class"]).to eq("StepperMotor::PerformStepJobV2")
    expect(job["scheduled_at"]).not_to be_nil

    scheduled_at = Time.parse(job["scheduled_at"])
    expect(scheduled_at).to be_within(5.seconds).of(40.minutes.from_now)
  end
end
