# frozen_string_literal: true

require "test_helper"

class RecoveryTest < ActiveSupport::TestCase
  setup do
    StepperMotor::Journey.delete_all
  end

  test "recovers a journey by reattempting it" do
    stuck_journey_class = create_journey_subclass do
      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end

      step :third, wait: 4.days do
      end
    end

    freeze_time
    journey = stuck_journey_class.create!

    journey.perform_next_step!
    assert_equal "second", journey.next_step_name

    travel_to Time.now + 5.days

    assert_equal :reattempt, stuck_journey_class.when_stuck
    assert_equal :reattempt, journey.when_stuck

    # Hang the journey in "performing"
    stuck_fiber = Fiber.new do
      journey.perform_next_step!
    end
    stuck_fiber.resume

    assert journey.persisted?
    assert journey.performing?
    assert_equal Time.now, journey.updated_at

    assert_not_includes StepperMotor::Journey.stuck(1.days.ago), journey

    travel_to Time.now + 2.days
    assert_includes StepperMotor::Journey.stuck(2.days.ago), journey

    perform_at_before_recovery = journey.next_step_to_be_performed_at
    assert_nothing_raised do
      journey.reload.recover!
    end

    journey.reload
    assert_equal perform_at_before_recovery, journey.next_step_to_be_performed_at
    assert_equal "second", journey.next_step_name
  end

  test "recovers a journey by canceling it" do
    stuck_journey_class = create_journey_subclass do
      self.when_stuck = :cancel

      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end

      step :third, wait: 4.days do
      end
    end

    freeze_time
    journey = stuck_journey_class.create!

    journey.perform_next_step!
    assert_equal "second", journey.next_step_name

    travel_to Time.now + 5.days

    assert_equal :cancel, stuck_journey_class.when_stuck
    assert_equal :cancel, journey.when_stuck

    # Hang the journey in "performing"
    stuck_fiber = Fiber.new do
      journey.perform_next_step!
    end
    stuck_fiber.resume

    assert journey.persisted?
    assert journey.performing?
    assert_equal Time.now, journey.updated_at

    travel_to Time.now + 2.days
    assert_includes StepperMotor::Journey.stuck(2.days.ago), journey

    assert_nothing_raised do
      journey.reload.recover!
    end

    journey.reload
    assert journey.canceled?
  end
end
