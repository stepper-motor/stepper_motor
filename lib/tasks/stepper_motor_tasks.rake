# frozen_string_literal: true

namespace :stepper_motor do
  desc "Recover all journeys hanging in the 'performing' state"
  task :recovery do
    StepperMotor::RecoverStuckJourneysJob.perform_now
  end
end
