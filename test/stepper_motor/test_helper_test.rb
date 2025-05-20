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

  test "is able to perform a single step forcibly" do
    journey = speedy_journey_class.create!
    assert journey.ready?

    SideEffects.clear!
    immediately_perform_single_step(journey, :step_2)
    assert SideEffects.produced?("step_2")
  end
end
