require "active_job"

class StepperMotor::PerformStepJob < ActiveJob::Base
  def perform(journey_gid)
    # Pass the GlobalID instead of the record itself, so that we can rescue the non-existing record
    # exception here as opposed to the job deserialization
    journey = begin
      GlobalID::Locator.locate(journey_gid)
    rescue ActiveRecord::RecordNotFound
      return # The journey has been canceled and destroyed previously or elsewhere
    end
    journey.perform_next_step!
  end
end