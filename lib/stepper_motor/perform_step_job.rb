# frozen_string_literal: true

require "active_job"

class StepperMotor::PerformStepJob < ActiveJob::Base
  def perform(*posargs, **kwargs)
    if posargs.length == 1 && kwargs.empty?
      perform_via_journey_gid(*posargs)
    else
      perform_via_kwargs(**kwargs)
    end
  end

  private

  def perform_via_journey_gid(journey_gid)
    # Pass the GlobalID instead of the record itself, so that we can rescue the non-existing record
    # exception here as opposed to the job deserialization
    journey = begin
      GlobalID::Locator.locate(journey_gid)
    rescue ActiveRecord::RecordNotFound
      return # The journey has been canceled and destroyed previously or elsewhere
    end
    journey.perform_next_step!
  end

  def perform_via_kwargs(journey_id:, journey_class_name:, idempotency_key: nil, **)
    journey = begin
      StepperMotor::Journey.find(journey_id)
    rescue ActiveRecord::RecordNotFound
      # The journey has been canceled and destroyed previously or elsewhere
      return
    end
    journey.perform_next_step!(idempotency_key: idempotency_key)
  end
end

# Alias for the previous job name
StepperMotor::PerformStepJobV2 = StepperMotor::PerformStepJob
