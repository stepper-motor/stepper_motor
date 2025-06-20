# frozen_string_literal: true

require "test_helper"

class FlowControlTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper

  test "can pause a Journey during a step" do
    pausing_journey = create_journey_subclass do
      step do
        SideEffects.touch! "before pausing"
        pause!
        SideEffects.touch! "after pausing"
      end
    end

    journey = pausing_journey.create!
    assert journey.ready?

    assert_produced_side_effects("before pausing") do
      assert_did_not_produce_side_effects("after pausing") do
        journey.perform_next_step!
      end
    end
    assert journey.paused?
  end

  test "schedules a job on resume" do
    pausing_journey = create_journey_subclass do
      step do
        SideEffects.touch! "after resume"
      end
    end

    journey = pausing_journey.create!
    journey.pause!
    assert journey.paused?

    clear_enqueued_jobs

    assert_produced_side_effects("after resume") do
      journey.resume!
      perform_enqueued_jobs
    end
  end

  test "changes the idempotency key at resume" do
    pausing_journey = create_journey_subclass do
      step do
        SideEffects.touch! "after resume"
      end
    end

    journey = pausing_journey.create!
    journey.pause!
    assert journey.paused?
    ik_before = journey.idempotency_key

    journey.resume!
    assert journey.persisted?
    refute_equal ik_before, journey.idempotency_key
  end

  test "does not perform the step on job that has been paused" do
    pausing_journey = create_journey_subclass do
      step do
        SideEffects.touch! "should not run"
      end
    end

    journey = pausing_journey.create!
    journey.pause!
    assert journey.paused?

    assert_no_side_effects { journey.perform_next_step! }
  end

  test "can skip a step and continue to next step" do
    skipping_journey = create_journey_subclass do
      step do
        SideEffects.touch! "before skipping"
        skip!
        SideEffects.touch! "after skipping"
      end

      step do
        SideEffects.touch! "second step"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    # First step should be skipped
    assert_produced_side_effects("before skipping") do
      assert_did_not_produce_side_effects("after skipping") do
        journey.perform_next_step!
      end
    end
    assert journey.ready?

    # Second step should be performed
    assert_produced_side_effects("second step") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "can skip the last step and finish the journey" do
    skipping_journey = create_journey_subclass do
      step do
        SideEffects.touch! "first step"
      end

      step do
        SideEffects.touch! "before skipping last"
        skip!
        SideEffects.touch! "after skipping last"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    # First step should be performed normally
    assert_produced_side_effects("first step") do
      journey.perform_next_step!
    end
    assert journey.ready?

    # Last step should be skipped and journey should finish
    assert_produced_side_effects("before skipping last") do
      assert_did_not_produce_side_effects("after skipping last") do
        journey.perform_next_step!
      end
    end
    assert journey.finished?
  end

  test "skip! can be called outside of a step for ready journeys" do
    skipping_journey = create_journey_subclass do
      step do
        SideEffects.touch! "first step"
      end

      step do
        SideEffects.touch! "second step"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    # Skip the first step from outside
    journey.skip!
    assert journey.ready?

    # The second step should now be scheduled
    assert_produced_side_effects("second step") do
      journey.perform_next_step!
    end
    assert journey.finished?
  end

  test "skip! outside of step raises error for non-ready journeys" do
    skipping_journey = create_journey_subclass do
      step do
        SideEffects.touch! "step completed"
      end
    end

    journey = skipping_journey.create!
    journey.pause!
    assert journey.paused?

    assert_raises(RuntimeError, "skip! can only be used on journeys in the `ready` state") do
      journey.skip!
    end
  end

  test "skip! outside of step can finish journey when skipping last step" do
    skipping_journey = create_journey_subclass do
      step do
        SideEffects.touch! "first step"
      end

      step do
        SideEffects.touch! "last step"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    # Perform first step
    assert_produced_side_effects("first step") do
      journey.perform_next_step!
    end
    assert journey.ready?

    # Skip the last step from outside
    journey.skip!
    assert journey.finished?
  end

  test "skip! outside of step handles missing step definitions gracefully" do
    skipping_journey = create_journey_subclass do
      step do
        SideEffects.touch! "step completed"
      end
    end

    journey = skipping_journey.create!
    assert journey.ready?

    # Manually set a non-existent next step
    journey.update!(next_step_name: "non_existent_step")

    # Skip should handle this gracefully and finish the journey
    journey.skip!
    assert journey.finished?
  end

  test "skip! aborts the current step execution" do
    skipping_journey = create_journey_subclass do
      step do
        SideEffects.touch! "before skip"
        skip!
        SideEffects.touch! "after skip"
      end
    end

    journey = skipping_journey.create!

    assert_produced_side_effects("before skip") do
      assert_did_not_produce_side_effects("after skip") do
        journey.perform_next_step!
      end
    end
  end
end
