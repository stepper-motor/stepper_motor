# frozen_string_literal: true

# The purpose of this job is to find journeys which have, for whatever reason, remained in the
# `performing` state for far longer than the journey is supposed to. At the moment it assumes
# any journey that stayed in `performing` for longer than 1 hour has hung. Add this job to your
# cron table and perform it regularly.
class StepperMotor::ReapHungJourneysJob < ActiveJob::Base
  def perform
    StepperMotor::Journey.where("state = 'performing' AND updated_at < ?", 1.hour.ago).find_each do |hung_journey|
      hung_journey.update!(state: "ready")
      StepperMotor.scheduler.schedule(hung_journey)
    end
  end
end
