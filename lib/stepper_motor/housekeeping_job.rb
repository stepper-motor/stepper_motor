# frozen_string_literal: true

class StepperMotor::HousekeepingJob < ActiveJob::Base
  def perform(**)
    SteperMotor::RecoverStuckJourneysJob.perform_later
    SteperMotor::DeleteCompletedJourneysJob.perform_later
  end
end
