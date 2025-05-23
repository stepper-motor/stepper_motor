# frozen_string_literal: true

require "active_job"

# The purpose of this job is to find journeys which have, for whatever reason, remained in the
# `performing` state for far longer than the journey is supposed to. At the moment it assumes
# any journey that stayed in `performing` for longer than 1 hour has hung. Add this job to your
# cron table and perform it regularly.
class StepperMotor::RecoverStuckJourneysJobV1 < ActiveJob::Base
  DEFAULT_STUCK_FOR = 2.days

  def perform(stuck_for: DEFAULT_STUCK_FOR)
    StepperMotor::Journey.stuck(stuck_for.ago).find_each do |journey|
      journey.recover!
    rescue => e
      Rails&.error&.report(e)
    end
  end
end
