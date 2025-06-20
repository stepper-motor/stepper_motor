# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class IfConditionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper
  include StepperMotor::TestHelper

  test "supports if: with symbol condition that returns true" do
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

  test "supports if: with symbol condition that returns false" do
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

  test "supports if: with block condition that returns true" do
    journey_class = create_journey_subclass do
      step :one, if: -> { hero.present? } do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!(hero: create_journey_subclass.create!)
    assert_produced_side_effects("step executed") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "supports if: with block condition that returns false" do
    journey_class = create_journey_subclass do
      step :one, if: -> { hero.nil? } do
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

  test "supports if: with block condition that accesses journey instance variables" do
    journey_class = create_journey_subclass do
      step :one, if: -> { @condition_met } do
        SideEffects.touch!("step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end

      def initialize(*args)
        super
        @condition_met = false
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    refute SideEffects.produced?("step executed")
  end

  test "supports if: with block condition that can be changed during journey execution" do
    journey_class = create_journey_subclass do
      step :one, if: -> { @condition_met } do
        SideEffects.touch!("first step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
        @condition_met = true
      end

      step :three, if: -> { @condition_met } do
        SideEffects.touch!("third step executed")
      end

      def initialize(*args)
        super
        @condition_met = false
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    assert SideEffects.produced?("third step executed")
    refute SideEffects.produced?("first step executed")
  end

  test "skips step when if: condition is false and continues to next step" do
    journey_class = create_journey_subclass do
      step :one, if: :false_condition do
        SideEffects.touch!("first step executed")
      end

      step :two do
        SideEffects.touch!("second step executed")
      end

      step :three do
        SideEffects.touch!("third step executed")
      end

      def false_condition
        false
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    assert SideEffects.produced?("second step executed")
    assert SideEffects.produced?("third step executed")
    refute SideEffects.produced?("first step executed")
  end

  test "skips step when if: condition is false and finishes journey if no more steps" do
    journey_class = create_journey_subclass do
      step :one, if: :false_condition do
        SideEffects.touch!("step executed")
      end

      def false_condition
        false
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    refute SideEffects.produced?("step executed")
  end

  test "supports if: with literal true" do
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

  test "supports if: with literal false" do
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

  test "supports if: with literal false and finishes journey if no more steps" do
    journey_class = create_journey_subclass do
      step :one, if: false do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    refute SideEffects.produced?("step executed")
  end

  test "defaults to true when if: is not specified" do
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

  test "treats nil as false in if condition" do
    journey_class = create_journey_subclass do
      step :one, if: nil do
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

  test "treats nil as false and finishes journey if no more steps" do
    journey_class = create_journey_subclass do
      step :one, if: nil do
        SideEffects.touch!("step executed")
      end
    end

    journey = journey_class.create!
    speedrun_journey(journey)
    refute SideEffects.produced?("step executed")
  end

  test "raises ArgumentError when if: condition is neither symbol nor callable" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step :one, if: "not a symbol or callable" do
          # noop
        end
      end
    end
  end

  test "passes if: parameter to step definition" do
    step_def = StepperMotor::Step.new(name: "a_step", seq: 1, on_exception: :reattempt!)
    assert_if_parameter = ->(**options) {
      assert options.key?(:if)
      assert_equal :test_condition, options[:if]
      # Return the original definition
      step_def
    }

    StepperMotor::Step.stub :new, assert_if_parameter do
      create_journey_subclass do
        step :test_step, if: :test_condition do
          # noop
        end
      end
    end
  end
end
