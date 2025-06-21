# frozen_string_literal: true

require "test_helper"

class TestHelperTest < ActiveSupport::TestCase
  include SideEffects::TestHelper
  include StepperMotor::TestHelper

  def speedy_journey_class
    create_journey_subclass do
      step :step_1, wait: 40.minutes do
        SideEffects.touch!("step_1")
      end

      step :step_2, wait: 2.days do
        SideEffects.touch!("step_2")
      end

      step do
        SideEffects.touch!("step_3")
      end
    end
  end

  test "speedruns the journey despite waits being configured" do
    journey = speedy_journey_class.create!
    assert journey.ready?

    SideEffects.clear!
    speedrun_journey(journey)
    assert SideEffects.produced?("step_1")
    assert SideEffects.produced?("step_2")
    assert SideEffects.produced?("step_3")
  end

  test "speedruns the journey with time travel by default" do
    journey = speedy_journey_class.create!
    assert journey.ready?

    original_time = Time.current
    SideEffects.clear!
    speedrun_journey(journey)
    assert SideEffects.produced?("step_1")
    assert SideEffects.produced?("step_2")
    assert SideEffects.produced?("step_3")

    # Calculate expected time difference: 40 minutes + 2 days + 1 second buffer per step
    expected_time_difference = 40.minutes + 2.days + 3.seconds

    # Verify that time has traveled forward by approximately the expected amount
    # (allowing for small execution time differences)
    assert_in_delta expected_time_difference, Time.current - original_time, 1.second
  end

  test "speedruns the journey without time travel when specified" do
    journey = speedy_journey_class.create!
    assert journey.ready?

    SideEffects.clear!
    speedrun_journey(journey, time_travel: false)
    assert SideEffects.produced?("step_1")
    assert SideEffects.produced?("step_2")
    assert SideEffects.produced?("step_3")
  end

  test "is able to perform a single step forcibly" do
    journey = speedy_journey_class.create!
    assert journey.ready?

    SideEffects.clear!
    immediately_perform_single_step(journey, :step_2)
    assert SideEffects.produced?("step_2")
  end
end
