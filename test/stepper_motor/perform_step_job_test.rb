require "test_helper"

class PerformStepJobTest < ActiveSupport::TestCase
  include SideEffects::TestHelper

  test "exposes the V2 variant in a constant to allow old jobs to be unserialized" do
    assert defined?(StepperMotor::PerformStepJobV2)
    assert_equal StepperMotor::PerformStepJob, StepperMotor::PerformStepJobV2
  end

  test "allows perform() with a GlobalID as argument" do
    journey = create_journey_subclass do
      step do
        # noop
      end
    end.create!

    assert_nothing_raised { StepperMotor::PerformStepJob.new.perform(journey.to_global_id) }
    assert journey.reload.finished?
  end

  test "allows perform() with the journey class name and ID" do
    journey = create_journey_subclass do
      step do
        # noop
      end
    end.create!

    assert_nothing_raised do
      StepperMotor::PerformStepJob.new.perform(journey_id: journey.id, journey_class_name: journey.class.name)
    end
    assert journey.reload.finished?
  end

  test "allows perform() with the journey class name, ID and idempotency key" do
    journey = create_journey_subclass do
      step do
        # noop
      end
    end.create!

    assert_nothing_raised do
      StepperMotor::PerformStepJob.new.perform(journey_id: journey.id, journey_class_name: journey.class.name, idempotency_key: journey.idempotency_key)
    end
    assert journey.reload.finished?
  end

  test "skips without exceptions if the idempotency key is incorrect" do
    journey = create_journey_subclass do
      step do
        # noop
      end
    end.create!

    assert_nothing_raised do
      StepperMotor::PerformStepJob.new.perform(journey_id: journey.id, journey_class_name: journey.class.name, idempotency_key: "wrong")
    end
    assert journey.reload.ready?
  end
end
