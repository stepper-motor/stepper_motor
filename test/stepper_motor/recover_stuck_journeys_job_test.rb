# frozen_string_literal: true

require "test_helper"

class RecoverStuckJourneysJobTest < ActiveSupport::TestCase
  setup do
    StepperMotor::Journey.delete_all
  end

  test "still has the previous job class name available to allow older jobs to be unserialized" do
    assert defined?(StepperMotor::RecoverStuckJourneysJobV1)
    assert_equal StepperMotor::RecoverStuckJourneysJob, StepperMotor::RecoverStuckJourneysJobV1
  end

  test "handles recovery from a background job" do
    stuck_journey_class1 = create_journey_subclass do
      self.when_stuck = :cancel

      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end
    end

    stuck_journey_class2 = create_journey_subclass do
      self.when_stuck = :reattempt

      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end
    end

    freeze_time

    journey_to_cancel = stuck_journey_class1.create!
    journey_to_reattempt = stuck_journey_class2.create!

    journey_to_cancel.perform_next_step!
    journey_to_reattempt.perform_next_step!

    travel_to Time.now + 5.days

    # Get both stuck
    Fiber.new do
      journey_to_cancel.perform_next_step!
    end.resume

    Fiber.new do
      journey_to_reattempt.perform_next_step!
    end.resume

    assert journey_to_cancel.reload.performing?
    assert journey_to_reattempt.reload.performing?

    StepperMotor::RecoverStuckJourneysJob.perform_now(stuck_for: 2.days)
    assert journey_to_cancel.reload.performing?
    assert journey_to_reattempt.reload.performing?

    travel_to Time.now + 2.days + 1.second
    StepperMotor::RecoverStuckJourneysJob.perform_now(stuck_for: 2.days)

    assert journey_to_cancel.reload.canceled?
    assert journey_to_reattempt.reload.ready?
  end

  test "does not raise when the class of the journey is no longer present" do
    stuck_journey_class1 = create_journey_subclass do
      self.when_stuck = :cancel

      step :first do
        Fiber.yield # Simulate the journey hanging
      end
    end

    freeze_time

    journey_to_cancel = stuck_journey_class1.create!
    Fiber.new do
      journey_to_cancel.perform_next_step!
    end.resume
    assert journey_to_cancel.reload.performing?

    journey_to_cancel.class.update_all(type: "UnknownJourneySubclass")

    assert_nothing_raised do
      StepperMotor::RecoverStuckJourneysJob.perform_now(stuck_for: 2.days)
    end
  end
end
