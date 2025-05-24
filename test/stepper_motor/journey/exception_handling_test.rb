# frozen_string_literal: true

require "test_helper"

class ExceptionHandlingTest < ActiveSupport::TestCase
  class CustomEx < StandardError
  end

  test "reattempts the failing step and bumps the idempotency key" do
    faulty_journey_class = create_journey_subclass do
      step on_exception: :reattempt! do
        raise CustomEx, "Something went wrong"
      end
    end

    faulty_journey = faulty_journey_class.create!
    assert faulty_journey.ready?
    ik_before_step = faulty_journey.idempotency_key

    assert_raises(CustomEx) { faulty_journey.perform_next_step! }

    assert faulty_journey.persisted?
    refute faulty_journey.changed?
    refute_equal faulty_journey.idempotency_key, ik_before_step
  end
end
