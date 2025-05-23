# frozen_string_literal: true

require "test_helper"

class JourneyIdempotencyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper

  test "does not perform the step if the idempotency key passed does not match the one stored" do
    journey_class = create_journey_subclass do
      step do
        raise "Should not happen"
      end
    end

    journey = journey_class.create!

    assert_predicate journey, :ready?
    assert journey.idempotency_key
    assert_nothing_raised do
      journey.perform_next_step!(idempotency_key: journey.idempotency_key + "n")
    end
    assert_predicate journey, :ready?
  end

  test "does perform the step if the idempotency key is set but not passed to perform_next_step!" do
    journey_class = create_journey_subclass do
      step do
        SideEffects.touch! :with_ik
      end
    end

    journey = journey_class.create!

    assert_predicate journey, :ready?
    assert journey.idempotency_key
    assert_produced_side_effects(:with_ik) do
      journey.perform_next_step!
    end
    assert_predicate journey, :finished?
  end

  test "updates the idempotency key when a step gets reattempted" do
    some_journey_class = create_journey_subclass do
      step :one do
        reattempt! wait: 2.minutes
      end
    end
    freeze_time

    journey = some_journey_class.create!

    assert_equal "one", journey.next_step_name
    assert journey.idempotency_key.present? # Since it was scheduled for the initial step
    previous_idempotency_key = journey.idempotency_key

    perform_enqueued_jobs # Should be reattempted

    journey.reload

    assert_equal "one", journey.next_step_name
    assert journey.idempotency_key
    refute_equal journey.idempotency_key, previous_idempotency_key
  end
end
