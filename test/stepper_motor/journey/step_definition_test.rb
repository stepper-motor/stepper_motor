# frozen_string_literal: true

require "test_helper"

class StepDefinitionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper

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
end
