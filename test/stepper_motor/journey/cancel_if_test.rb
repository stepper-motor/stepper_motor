# frozen_string_literal: true

require "test_helper"

class CancelIfTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper

  test "cancel_if with block condition cancels journey when true" do
    canceling_journey = create_journey_subclass do
      cancel_if { true }

      step do
        SideEffects.touch! "should not run"
      end
    end

    journey = canceling_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.canceled?
  end

  test "cancel_if with block condition does not cancel journey when false" do
    canceling_journey = create_journey_subclass do
      cancel_if { false }

      step do
        SideEffects.touch! "should run"
      end
    end

    journey = canceling_journey.create!
    assert journey.ready?

    assert_produced_side_effects("should run") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "cancel_if with symbol method call in block" do
    canceling_journey = create_journey_subclass do
      cancel_if { should_cancel? }

      step do
        SideEffects.touch! "should not run"
      end

      def should_cancel?
        true
      end
    end

    journey = canceling_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.canceled?
  end

  test "multiple cancel_if calls are all evaluated" do
    canceling_journey = create_journey_subclass do
      cancel_if { false }
      cancel_if { true }

      step do
        SideEffects.touch! "should not run"
      end
    end

    journey = canceling_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.canceled?
  end

  test "cancel_if conditions are evaluated after setting state to performing" do
    canceling_journey = create_journey_subclass do
      cancel_if { performing? }

      step do
        SideEffects.touch! "should not run"
      end
    end

    journey = canceling_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.canceled?
  end

  test "cancel_if with no block raises error" do
    assert_raises(ArgumentError, "cancel_if requires a block") do
      create_journey_subclass do
        cancel_if
      end
    end
  end

  test "cancel_if conditions are class-inheritable" do
    parent_journey = create_journey_subclass do
      cancel_if { true }
    end

    child_journey = create_journey_subclass(parent_journey) do
      step do
        SideEffects.touch! "should not run"
      end
    end

    journey = child_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.canceled?
  end

  test "cancel_if conditions are appendable in subclasses" do
    parent_journey = create_journey_subclass do
      cancel_if { false }
    end

    child_journey = create_journey_subclass(parent_journey) do
      cancel_if { true }

      step do
        SideEffects.touch! "should not run"
      end
    end

    journey = child_journey.create!
    assert journey.ready?

    assert_no_side_effects { journey.perform_next_step! }
    assert journey.canceled?
  end
end
