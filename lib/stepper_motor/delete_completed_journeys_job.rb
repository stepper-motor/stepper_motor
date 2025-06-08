# frozen_string_literal: true

# The purpose of this job is to find journeys which have completed (finished or canceled) some
# time ago and to delete them. The time is configured in the initializer.
class StepperMotor::DeleteCompletedJourneysJob < ActiveJob::Base
  def perform(completed_for: StepperMotor.delete_completed_journeys_after, **)
    return unless completed_for.present?

    scope = StepperMotor::Journey.where(state: ["finished", "canceled"], updated_at: ..completed_for.ago)
    scope.in_batches.each do |rel|
      rel.delete_all
    rescue => e
      Rails.try(:error).try(:report, e)
    end
  end
end
