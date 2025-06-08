# frozen_string_literal: true

class StepperMotor::HousekeepingJob < StepperMotor::BaseJob
  def perform(**)
    StepperMotor::RecoverStuckJourneysJob.perform_later
    StepperMotor::DeleteCompletedJourneysJob.perform_later
  end
end
