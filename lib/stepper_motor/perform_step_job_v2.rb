# frozen_string_literal: true

require "active_job"

class StepperMotor::PerformStepJobV2 < ActiveJob::Base
  def perform(journey_id:, journey_class_name:, **)
    journey = StepperMotor::Journey.find(journey_id)
    journey.perform_next_step!
  rescue ActiveRecord::RecordNotFound
    return # The journey has been canceled and destroyed previously or elsewhere
  end
end
