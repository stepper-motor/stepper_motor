# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class StepDefinitionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper
  include StepperMotor::TestHelper

  test "requires either a block or a name" do
    assert_raises(StepperMotor::StepConfigurationError) do
      create_journey_subclass do
        step
      end
    end
  end

  test "passes any additional options to the step definition" do
    step_def = StepperMotor::Step.new(name: "a_step", seq: 1, on_exception: :reattempt!)
    assert_extra_arguments = ->(**options) {
      assert options.key?(:extra)
      # Return the original definition
      step_def
    }

    StepperMotor::Step.stub :new, assert_extra_arguments do
      create_journey_subclass do
        step extra: true do
          # noop
        end
      end
    end
  end

  test "returns the created step definition" do
    test_case = self # To pass it into the class_eval of create_journey_subclass
    create_journey_subclass do
      step_def1 = step do
        # noop
      end

      step_def2 = step :another_step do
        # noop
      end

      test_case.assert_kind_of StepperMotor::Step, step_def1
      test_case.assert_kind_of StepperMotor::Step, step_def2
      test_case.assert_equal "another_step", step_def2.name
    end
  end

  test "allows steps to be defined as instance method names" do
    journey_class = create_journey_subclass do
      step :one
      step :two

      def one
        SideEffects.touch!("from method one")
      end

      def two
        SideEffects.touch!("from method two")
      end
    end

    journey = journey_class.create!

    assert_produced_side_effects("from method one", "from method two") do
      2.times { journey.perform_next_step! }
    end

    assert journey.finished?
  end

  test "raises a custom NoMethodError when a blockless step was defined but no method to carry it" do
    journey_class = create_journey_subclass do
      step :one
    end

    journey = journey_class.create!

    ex = assert_raises(NoMethodError) do
      journey.perform_next_step!
    end

    assert_kind_of NoMethodError, ex
    assert_match(/No block or method/, ex.message)
  end

  test "allows `step def'" do
    journey_class = create_journey_subclass do
      step def one
        SideEffects.touch!(:woof)
      end
    end

    journey = journey_class.create!
    assert_produced_side_effects(:woof) do
      journey.perform_next_step!
    end
  end

  test "adds steps to step_definitions" do
    journey_class = create_journey_subclass do
      step :one do
        # noop
      end
      step :two, wait: 20.minutes do
        # noop
      end
    end

    assert_kind_of Array, journey_class.step_definitions
    assert_equal 2, journey_class.step_definitions.length

    step_one, step_two = *journey_class.step_definitions

    assert_equal "one", step_one.name
    assert_equal 0, step_one.wait

    assert_equal "two", step_two.name
    assert_equal 20.minutes, step_two.wait
  end

  test "gives automatic names to anonymous steps" do
    journey_class = create_journey_subclass do
      step :one do
        # noop
      end
      step wait: 20.minutes do
        # noop
      end
    end

    assert_kind_of Array, journey_class.step_definitions
    assert_equal 2, journey_class.step_definitions.length

    step_one, step_two = *journey_class.step_definitions

    assert_equal "one", step_one.name
    assert_equal "step_2", step_two.name
  end

  test "does not allow invalid values for after: and wait:" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step after: 10.hours do
          # pass
        end

        step after: 5.hours do
          # pass
        end
      end
    end

    assert_raises(ArgumentError) do
      create_journey_subclass do
        step wait: -5.hours do
          # pass
        end
      end
    end

    assert_raises(ArgumentError) do
      create_journey_subclass do
        step after: 5.hours, wait: 2.seconds do
          # pass
        end
      end
    end
  end

  test "forbids multiple steps with the same name within a journey" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step :foo do
          true
        end

        step "foo" do
          true
        end
      end
    end
  end

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
end
