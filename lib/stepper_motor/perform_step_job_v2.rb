# frozen_string_literal: true

class StepperMotor::PerformStepJobV2 < ActiveJob::Base
  def perform(journey_id:, journey_class_name:, idempotency_key: nil, **)
    journey = StepperMotor::Journey.find(journey_id)
    journey.perform_next_step!(idempotency_key: idempotency_key)
  rescue ActiveRecord::RecordNotFound
    # The journey has been canceled and destroyed previously or elsewhere
  end
end
