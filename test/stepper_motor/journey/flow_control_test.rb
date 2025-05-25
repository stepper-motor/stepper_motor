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
end
