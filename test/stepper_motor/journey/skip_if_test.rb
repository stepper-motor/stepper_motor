# frozen_string_literal: true

require "test_helper"

class SkipIfTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper

  test "skip_if with block condition skips step when true" do
    skipping_journey = create_journey_subclass do
      skip_if { true }

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with block condition does not skip step when false" do
    skipping_journey = create_journey_subclass do
      skip_if { false }

      step do
        SideEffects.touch! "should run"
      end

      step do
        SideEffects.touch! "should also run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should also run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with boolean argument skips step when true" do
    skipping_journey = create_journey_subclass do
      skip_if true

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with boolean argument does not skip step when false" do
    skipping_journey = create_journey_subclass do
      skip_if false

      step do
        SideEffects.touch! "should run"
      end

      step do
        SideEffects.touch! "should also run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should also run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with symbol argument calls method on journey" do
    skipping_journey = create_journey_subclass do
      skip_if :should_skip?

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end

      def should_skip?
        true
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with symbol method call in block" do
    skipping_journey = create_journey_subclass do
      skip_if { should_skip? }

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end

      def should_skip?
        true
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with array argument skips when all conditions are true" do
    skipping_journey = create_journey_subclass do
      skip_if [true, true]

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with array argument does not skip when any condition is false" do
    skipping_journey = create_journey_subclass do
      skip_if [true, false]

      step do
        SideEffects.touch! "should run"
      end

      step do
        SideEffects.touch! "should also run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should also run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with proc argument evaluates proc in journey context" do
    proc_condition = -> { true }

    skipping_journey = create_journey_subclass do
      skip_if proc_condition

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with conditional object works correctly" do
    conditional = StepperMotor::Conditional.new(true)

    skipping_journey = create_journey_subclass do
      skip_if conditional

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with nil argument does not skip step" do
    skipping_journey = create_journey_subclass do
      skip_if nil

      step do
        SideEffects.touch! "should run"
      end

      step do
        SideEffects.touch! "should also run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should also run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "multiple skip_if calls are all evaluated" do
    skipping_journey = create_journey_subclass do
      skip_if false
      skip_if true

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if conditions are evaluated after setting state to performing" do
    skipping_journey = create_journey_subclass do
      skip_if { performing? }

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if with no arguments and no block raises error" do
    assert_raises(ArgumentError, "skip_if requires either a condition argument or a block") do
      create_journey_subclass do
        skip_if
      end
    end
  end

  test "skip_if with both argument and block raises error" do
    assert_raises(ArgumentError, "skip_if accepts either a condition argument or a block, but not both") do
      create_journey_subclass do
        skip_if true do
          false
        end
      end
    end
  end

  test "skip_if conditions are class-inheritable" do
    parent_journey = create_journey_subclass do
      skip_if true
    end

    child_journey = create_journey_subclass(parent_journey) do
      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = child_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if conditions are appendable in subclasses" do
    parent_journey = create_journey_subclass do
      skip_if false
    end

    child_journey = create_journey_subclass(parent_journey) do
      skip_if true

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = child_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if on last step finishes journey" do
    skipping_journey = create_journey_subclass do
      skip_if { true }

      step do
        SideEffects.touch! "should not run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.finished?
  end

  test "skip_if works with named steps" do
    skipping_journey = create_journey_subclass do
      skip_if { true }

      step :first_step do
        SideEffects.touch! "should not run"
      end

      step :second_step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "second_step", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if works with steps that have wait times" do
    skipping_journey = create_journey_subclass do
      skip_if { true }

      step :first_step, wait: 1.hour do
        SideEffects.touch! "should not run"
      end

      step :second_step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "second_step", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip_if and cancel_if work together - skip_if takes precedence" do
    mixed_journey = create_journey_subclass do
      skip_if { true }
      cancel_if { true }

      step do
        SideEffects.touch! "should not run"
      end

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = mixed_journey.create!
    assert journey.ready?

    # skip_if should be checked first and skip the step
    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "step_2", journey.next_step_name

    # Now cancel_if should cancel the journey
    assert_no_side_effects { journey.perform_next_step! }
    assert journey.canceled?
  end

  test "skip_if works with steps that have on_exception handlers" do
    skipping_journey = create_journey_subclass do
      skip_if { true }

      step :first_step, on_exception: :cancel! do
        SideEffects.touch! "should not run"
      end

      step :second_step do
        SideEffects.touch! "should run"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.ready?
    assert_equal "second_step", journey.next_step_name

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end
end 