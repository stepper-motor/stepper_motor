require "test_helper"

class CompletedJourneysCleanupTest < ActiveSupport::TestCase
  include SideEffects::TestHelper

  test "defines a variable on StepperMotor and sets it to a default value" do
    assert StepperMotor.delete_completed_journeys_after
    assert_equal 30.days, StepperMotor.delete_completed_journeys_after
  end

  test "cleans up finished journeys" do
    previous_setting = StepperMotor.delete_completed_journeys_after

    journey_class = create_journey_subclass do
      step wait: 20.minutes do
        SideEffects.touch! :a_step
      end
    end
    journey = journey_class.create!
    another_journey = journey_class.create!

    assert_no_changes "StepperMotor::Journey.count" do
      StepperMotor::DeleteCompletedJourneysJob.new.perform
    end

    travel_to Time.current + 20.minutes + 1.second
    journey.perform_next_step!

    assert SideEffects.produced?(:a_step)
    assert journey.finished?

    assert_no_changes "StepperMotor::Journey.count" do
      StepperMotor::DeleteCompletedJourneysJob.new.perform
    end

    StepperMotor.delete_completed_journeys_after = 7.minutes
    travel_to Time.current + 7.minutes + 1.second

    assert_changes "StepperMotor::Journey.count", -1 do
      StepperMotor::DeleteCompletedJourneysJob.new.perform
    end

    assert_raises(ActiveRecord::RecordNotFound) { journey.reload }
    assert_nothing_raised { another_journey.reload }
  ensure
    StepperMotor.delete_completed_journeys_after = previous_setting
  end

  test "cleans up canceled journeys" do
    previous_setting = StepperMotor.delete_completed_journeys_after

    journey_class = create_journey_subclass do
      step wait: 20.minutes do
        # noop
      end
    end
    journey = journey_class.create!
    journey.cancel!

    assert_no_changes "StepperMotor::Journey.count" do
      StepperMotor::DeleteCompletedJourneysJob.new.perform
    end

    StepperMotor.delete_completed_journeys_after = 7.minutes
    travel_to Time.current + 7.minutes + 1.second

    assert_changes "StepperMotor::Journey.count", -1 do
      StepperMotor::DeleteCompletedJourneysJob.new.perform
    end

    assert_raises(ActiveRecord::RecordNotFound) { journey.reload }
  ensure
    StepperMotor.delete_completed_journeys_after = previous_setting
  end

  test "does not delete any journeys if the setting is set to nil" do
    previous_setting = StepperMotor.delete_completed_journeys_after
    StepperMotor.delete_completed_journeys_after = nil

    journey_class = create_journey_subclass do
      step wait: 20.minutes do
        # noop
      end
    end
    journey = journey_class.create!
    journey.cancel!

    travel_to Time.current + 365.days
    assert_no_changes "StepperMotor::Journey.count" do
      StepperMotor::DeleteCompletedJourneysJob.new.perform
    end
    assert_nothing_raised { journey.reload }
  ensure
    StepperMotor.delete_completed_journeys_after = previous_setting
  end
end
