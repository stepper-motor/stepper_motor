# frozen_string_literal: true

require "test_helper"

class ExceptionHandlingTest < ActiveSupport::TestCase
  # See below.
  self.use_transactional_tests = false

  class CustomEx < StandardError
  end

  test "with :reattempt!, reattempts the failing step and bumps the idempotency key" do
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
    assert faulty_journey.ready?
    refute_equal faulty_journey.idempotency_key, ik_before_step
  end

  test "with :cancel!, cancels at the failig step" do
    faulty_journey_class = create_journey_subclass do
      step on_exception: :cancel! do
        raise CustomEx, "Something went wrong"
      end
    end

    faulty_journey = faulty_journey_class.create!
    assert faulty_journey.ready?
    faulty_journey.idempotency_key

    assert_raises(CustomEx) { faulty_journey.perform_next_step! }

    assert faulty_journey.persisted?
    refute faulty_journey.changed?
    assert faulty_journey.canceled?
  end

  test "is able to get the journey into reattempt even if the step has caused an invalid transaction" do
    # We need to test a situation where a Journey causes a database transaction
    # becoming invalid due to an invalid statement. Since we work with the same database
    # as the code of the step, we won't be able to perform any SQL statments if the transaction
    # gets left in the broken state and is not rolled back before we try to persist the failing
    # Journey.

    faulty_journey_class = create_journey_subclass do
      step on_exception: :reattempt! do
        StepperMotor::Journey.connection.execute("KERFUFFLE")
      end
    end

    faulty_journey = faulty_journey_class.create!
    assert faulty_journey.ready?
    ik_before_step = faulty_journey.idempotency_key
    assert_raises(ActiveRecord::StatementInvalid) { faulty_journey.perform_next_step! }

    assert faulty_journey.persisted?
    refute faulty_journey.changed?
    refute_equal faulty_journey.idempotency_key, ik_before_step
  end
end
