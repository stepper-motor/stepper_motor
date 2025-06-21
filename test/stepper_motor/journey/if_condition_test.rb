# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class IfConditionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper
  include StepperMotor::TestHelper

  test "supports skip_if: with symbol condition that returns false (performs step)" do
    journey_class = create_journey_subclass do
      step :one, skip_if: :should_skip do
        SideEffects.touch!("step executed")
      end

      def should_skip
        false
      end
    end

    journey = journey_class.create!
    assert_produced_side_effects("step executed") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "supports skip_if: with symbol condition that returns true (skips step)" do
    journey_class = create_journey_subclass do
      step :one, skip_if: :should_skip do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end

      def should_skip
        true
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    refute SideEffects.produced?("step executed")
  end

  test "supports skip_if: with block condition that returns false (performs step)" do
    journey_class = create_journey_subclass do
      step :one, skip_if: -> { hero.nil? } do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!(hero: create_journey_subclass.create!)
    assert_produced_side_effects("step executed") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "supports skip_if: with block condition that returns true (skips step)" do
    journey_class = create_journey_subclass do
      step :one, skip_if: -> { hero.present? } do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end
    end

    journey = journey_class.create!(hero: create_journey_subclass.create!)
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    refute SideEffects.produced?("step executed")
  end

  test "supports skip_if: with block condition that accesses journey instance variables" do
    journey_class = create_journey_subclass do
      step :one, skip_if: -> { @condition_met } do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end

      def initialize(*args)
        super
        @condition_met = true
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    refute SideEffects.produced?("step executed")
  end

  test "supports skip_if: with block condition that can be changed during journey execution" do
    journey_class = create_journey_subclass do
      step :one, skip_if: -> { @condition_met } do
        SideEffects.touch!("first step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
        @condition_met = false
      end

      step :three, skip_if: -> { @condition_met } do
        SideEffects.touch!("third step executed")
      end

      def initialize(*args)
        super
        @condition_met = true
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    assert SideEffects.produced?("third step executed")
    refute SideEffects.produced?("first step executed")
  end

  test "skips step when skip_if: condition is true and continues to next step" do
    journey_class = create_journey_subclass do
      step :one, skip_if: :true_condition do
        SideEffects.touch!("first step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end

      step :three do
        SideEffects.touch!("third step executed")
      end

      def true_condition
        true
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    assert SideEffects.produced?("third step executed")
    refute SideEffects.produced?("first step executed")
  end

  test "skips step when skip_if: condition is true and finishes journey if no more steps" do
    journey_class = create_journey_subclass do
      step :one, skip_if: :true_condition do
        SideEffects.touch!("step executed")
      end

      def true_condition
        true
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    refute SideEffects.produced?("step executed")
  end

  test "supports skip_if: with literal false (performs step)" do
    journey_class = create_journey_subclass do
      step :one, skip_if: false do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!
    assert_produced_side_effects("step executed") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "supports skip_if: with literal true (skips step)" do
    journey_class = create_journey_subclass do
      step :one, skip_if: true do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    refute SideEffects.produced?("step executed")
  end

  test "supports skip_if: with literal true and finishes journey if no more steps" do
    journey_class = create_journey_subclass do
      step :one, skip_if: true do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    refute SideEffects.produced?("step executed")
  end

  test "defaults to false when skip_if: is not specified" do
    journey_class = create_journey_subclass do
      step :one do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!
    assert_produced_side_effects("step executed") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "treats nil as false in skip_if condition (performs step)" do
    journey_class = create_journey_subclass do
      step :one, skip_if: nil do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("step executed")
    assert SideEffects.produced?("second step executed")
  end

  test "raises ArgumentError when skip_if: condition is neither symbol nor callable" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step :one, skip_if: "not a symbol or callable" do
          # noop
        end
      end
    end
  end

  test "passes skip_if: parameter to step definition" do
    step_def = StepperMotor::Step.new(name: "a_step", on_exception: :reattempt!)
    assert_skip_if_parameter = ->(**options) {
      assert options.key?(:skip_if)
      assert_equal :test_condition, options[:skip_if]
      # Return the original definition
      step_def
    }

    StepperMotor::Step.stub :new, assert_skip_if_parameter do
      create_journey_subclass do
        step :test_step, skip_if: :test_condition do
          # noop
        end
      end
    end
  end

  # Backward compatibility tests for if: parameter
  test "supports if: with symbol condition that returns true (performs step, backward compatibility)" do
    journey_class = create_journey_subclass do
      step :one, if: :should_run do
        SideEffects.touch!("step executed")
      end

      def should_run
        true
      end
    end

    journey = journey_class.create!
    assert_produced_side_effects("step executed") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "supports if: with symbol condition that returns false (skips step, backward compatibility)" do
    journey_class = create_journey_subclass do
      step :one, if: :should_run do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end

      def should_run
        false
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    refute SideEffects.produced?("step executed")
  end

  test "supports if: with literal true (performs step, backward compatibility)" do
    journey_class = create_journey_subclass do
      step :one, if: true do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!
    assert_produced_side_effects("step executed") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "supports if: with literal false (skips step, backward compatibility)" do
    journey_class = create_journey_subclass do
      step :one, if: false do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    refute SideEffects.produced?("step executed")
  end

  test "raises error when both skip_if: and if: are specified" do
    assert_raises(StepperMotor::StepConfigurationError) do
      create_journey_subclass do
        step :one, skip_if: :condition1, if: :condition2 do
          # noop
        end
      end
    end
  end
end
