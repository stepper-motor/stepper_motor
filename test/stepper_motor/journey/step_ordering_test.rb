# frozen_string_literal: true

require "test_helper"

class StepOrderingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper
  include StepperMotor::TestHelper

  test "allows inserting step before another step using string" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :third do
        # noop
      end
      step :second, before_step: "first" do
        # noop
      end
    end

    assert_equal ["second", "first", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows inserting step before another step using symbol" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :third do
        # noop
      end
      step :second, before_step: :first do
        # noop
      end
    end

    assert_equal ["second", "first", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows inserting step after another step using string" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :third do
        # noop
      end
      step :second, after_step: "first" do
        # noop
      end
    end

    assert_equal ["first", "second", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows inserting step after another step using symbol" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :third do
        # noop
      end
      step :second, after_step: :first do
        # noop
      end
    end

    assert_equal ["first", "second", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows inserting step at the beginning using before_step" do
    journey_class = create_journey_subclass do
      step :second do
        # noop
      end
      step :third do
        # noop
      end
      step :first, before_step: "second" do
        # noop
      end
    end

    assert_equal ["first", "second", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows inserting step at the end using after_step" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :second do
        # noop
      end
      step :third, after_step: "second" do
        # noop
      end
    end

    assert_equal ["first", "second", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows complex step ordering with multiple insertions" do
    journey_class = create_journey_subclass do
      step :step_1 do
        # noop
      end
      step :step_4 do
        # noop
      end
      step :step_2, after_step: "step_1" do
        # noop
      end
      step :step_3, before_step: "step_4" do
        # noop
      end
    end

    assert_equal ["step_1", "step_2", "step_3", "step_4"], journey_class.step_definitions.map(&:name)
  end

  test "raises error when both before_step and after_step are specified" do
    assert_raises(StepperMotor::StepConfigurationError, "Either before_step: or after_step: can be specified, but not both") do
      create_journey_subclass do
        step :first do
          # noop
        end
        step :second, before_step: "first", after_step: "first" do
          # noop
        end
      end
    end
  end

  test "raises error when before_step references non-existent step" do
    assert_raises(StepperMotor::StepConfigurationError, "Step named \"nonexistent\" not found for before_step: parameter") do
      create_journey_subclass do
        step :first, before_step: "nonexistent" do
          # noop
        end
      end
    end
  end

  test "raises error when after_step references non-existent step" do
    assert_raises(StepperMotor::StepConfigurationError, "Step named \"nonexistent\" not found for after_step: parameter") do
      create_journey_subclass do
        step :first, after_step: "nonexistent" do
          # noop
        end
      end
    end
  end

  test "maintains existing after: timing functionality" do
    journey_class = create_journey_subclass do
      step :first, after: 5.minutes do
        # noop
      end
      step :second, after: 10.minutes do
        # noop
      end
    end

    assert_equal ["first", "second"], journey_class.step_definitions.map(&:name)
    assert_equal 5.minutes, journey_class.step_definitions[0].wait
    assert_equal 5.minutes, journey_class.step_definitions[1].wait
  end

  test "allows mixing step ordering with timing" do
    journey_class = create_journey_subclass do
      step :first, wait: 1.minute do
        # noop
      end
      step :third, after_step: "first" do
        # noop
      end
      step :second, before_step: "third", wait: 2.minutes do
        # noop
      end
    end

    assert_equal ["first", "second", "third"], journey_class.step_definitions.map(&:name)
    assert_equal 1.minute, journey_class.step_definitions[0].wait
    assert_equal 2.minutes, journey_class.step_definitions[1].wait
    assert_equal 0, journey_class.step_definitions[2].wait
  end

  test "allows inserting step with method name" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :third do
        # noop
      end
      step :second, after_step: "first"

      def second
        # noop
      end
    end

    assert_equal ["first", "second", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows inserting step with automatic name generation" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :third do
        # noop
      end
      step before_step: "third" do
        # noop
      end
    end

    assert_equal ["first", "step_3", "third"], journey_class.step_definitions.map(&:name)
  end

  test "allows inserting step with additional options" do
    journey_class = create_journey_subclass do
      step :first do
        # noop
      end
      step :third do
        # noop
      end
      step :second, after_step: "first", on_exception: :skip! do
        # noop
      end
    end

    assert_equal ["first", "second", "third"], journey_class.step_definitions.map(&:name)
    assert_equal :skip!, journey_class.step_definitions[1].instance_variable_get(:@on_exception)
  end

  test "allows inserting steps before or after steps defined in superclass" do
    parent_class = create_journey_subclass do
      step :parent_first do
        # noop
      end
      step :parent_last do
        # noop
      end
    end

    child_class = create_journey_subclass(parent_class) do
      step :child_before, before_step: "parent_first" do
        # noop
      end
      step :child_after, after_step: "parent_last" do
        # noop
      end
      step :child_middle, after_step: "parent_first" do
        # noop
      end
    end

    assert_equal ["child_before", "parent_first", "child_middle", "parent_last", "child_after"], child_class.step_definitions.map(&:name)
  end
end
