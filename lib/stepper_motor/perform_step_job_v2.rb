# frozen_string_literal: true

require "active_job"

class StepperMotor::PerformStepJobV2 < ActiveJob::Base
  def perform(journey_id:, journey_class_name:, idempotency_key: nil, task_handle_id: nil, **)
    if task_handle_id
      perform_via_task_handle_id(journey_id, task_handle_id, idempotency_key)
    else
      perform_via_journey_id(journey_id, idempotency_key)
    end
  rescue ActiveRecord::RecordNotFound
    # The journey has been canceled and destroyed previously or elsewhere
  end

  private

  def perform_via_task_handle_id(journey_id, task_handle_id, idempotency_key)
    journey = StepperMotor::TaskHandle.includes(:journey).where(idempotency_key:).find(task_handle_id).journey
    journey.perform_next_step!(idempotency_key:)
  end

  def perform_via_journey_id(journey_id, idempotency_key)
    journey = StepperMotor::Journey.find(journey_id)
    journey.perform_next_step!(idempotency_key:)
  end
end
