# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "RecoveryStuckJourneysJobV1" do
  before do
    StepperMotor::Journey.delete_all
  end

  it "handles recovery from a background job" do
    stuck_journey_class1 = create_journey_subclass do
      self.when_stuck = :cancel

      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end
    end

    stuck_journey_class2 = create_journey_subclass do
      self.when_stuck = :reattempt

      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end
    end

    freeze_time

    journey_to_cancel = stuck_journey_class1.create!
    journey_to_reattempt = stuck_journey_class2.create!

    journey_to_cancel.perform_next_step!
    journey_to_reattempt.perform_next_step!

    travel_to Time.now + 5.days

    # Get both stuck
    Fiber.new do
      journey_to_cancel.perform_next_step!
    end.resume

    Fiber.new do
      journey_to_reattempt.perform_next_step!
    end.resume

    expect(journey_to_cancel.reload).to be_performing
    expect(journey_to_reattempt.reload).to be_performing

    StepperMotor::RecoverStuckJourneysJobV1.perform_now(stuck_for: 2.days)
    expect(journey_to_cancel.reload).to be_performing
    expect(journey_to_reattempt.reload).to be_performing

    travel_to Time.now + 2.days + 1.second
    StepperMotor::RecoverStuckJourneysJobV1.perform_now(stuck_for: 2.days)

    expect(journey_to_cancel.reload).to be_canceled
    expect(journey_to_reattempt.reload).to be_ready
  end

  it "does not raise when the class of the journey is no longer present" do
    stuck_journey_class1 = create_journey_subclass do
      self.when_stuck = :cancel

      step :first do
        Fiber.yield # Simulate the journey hanging
      end
    end

    freeze_time

    journey_to_cancel = stuck_journey_class1.create!
    Fiber.new do
      journey_to_cancel.perform_next_step!
    end.resume
    expect(journey_to_cancel.reload).to be_performing

    journey_to_cancel.class.update_all(type: "UnknownJourneySubclass")

    expect {
      StepperMotor::RecoverStuckJourneysJobV1.perform_now(stuck_for: 2.days)
    }.not_to raise_error
  end
end
