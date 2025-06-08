# frozen_string_literal: true

require "test_helper"

class ForwardSchedulerTest < ActiveSupport::TestCase
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

  test "schedules a journey 40 minutes ahead" do
    scheduler = StepperMotor::ForwardScheduler.new
    StepperMotor.scheduler = scheduler

    _journey = far_future_journey_class.create!

    assert_equal 1, enqueued_jobs.size
    job = enqueued_jobs.first

    assert_equal "StepperMotor::PerformStepJob", job["job_class"]
    assert_not_nil job["scheduled_at"]

    scheduled_at = Time.parse(job["scheduled_at"])
    assert_in_delta 40.minutes.from_now.to_f, scheduled_at.to_f, 5.seconds.to_f
  end
end
