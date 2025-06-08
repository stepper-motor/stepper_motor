# frozen_string_literal: true

class StepperMotor::HousekeepingJob < ActiveJob::Base
  def perform(**)
    StepperMotor::RecoverStuckJourneysJob.perform_later
    StepperMotor::DeleteCompletedJourneysJob.perform_later
  end
end
