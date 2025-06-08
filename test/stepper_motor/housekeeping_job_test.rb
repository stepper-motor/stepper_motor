require "test_helper"

class HousekeepingJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "runs without exceptions and enqueues the two actual jobs" do
    assert_nothing_raised do
      StepperMotor::HousekeepingJob.perform_now
    end

    assert_enqueued_jobs 2
  end
end
