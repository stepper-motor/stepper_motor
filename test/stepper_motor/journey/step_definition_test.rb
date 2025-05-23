# frozen_string_literal: true

require "test_helper"

class StepDefinitionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
