# frozen_string_literal: true

require "test_helper"

class RecoveryTest < ActiveSupport::TestCase
  setup do
    StepperMotor::Journey.delete_all
  end

  it "recovers a journey by reattempting it" do
    stuck_journey_class = create_journey_subclass do
      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end

      step :third, wait: 4.days do
      end
    end

    freeze_time
    journey = stuck_journey_class.create!

    journey.perform_next_step!
    expect(journey.next_step_name).to eq("second")

    travel_to Time.now + 5.days

    expect(stuck_journey_class.when_stuck).to eq(:reattempt)
    expect(journey.when_stuck).to eq(:reattempt)

    # Hang the journey in "performing"
    stuck_fiber = Fiber.new do
      journey.perform_next_step!
    end
    stuck_fiber.resume

    expect(journey).to be_persisted
    expect(journey).to be_performing
    expect(journey.updated_at).to eq(Time.now)

    expect(StepperMotor::Journey.stuck(1.days.ago)).not_to include(journey)

    travel_to Time.now + 2.days
    expect(StepperMotor::Journey.stuck(2.days.ago)).to include(journey)

    perform_at_before_recovery = journey.next_step_to_be_performed_at
    expect {
      journey.reload.recover!
    }.not_to raise_error

    journey.reload
    expect(journey.next_step_to_be_performed_at).to eq(perform_at_before_recovery)
    expect(journey.next_step_name).to eq("second")
  end

  it "recovers a journey by canceling it" do
    stuck_journey_class = create_journey_subclass do
      self.when_stuck = :cancel

      step :first do
      end

      step :second, wait: 4.days do
        Fiber.yield # Simulate the journey hanging
      end

      step :third, wait: 4.days do
      end
    end

    freeze_time
    journey = stuck_journey_class.create!

    journey.perform_next_step!
    expect(journey.next_step_name).to eq("second")

    travel_to Time.now + 5.days

    expect(stuck_journey_class.when_stuck).to eq(:cancel)
    expect(journey.when_stuck).to eq(:cancel)

    # Hang the journey in "performing"
    stuck_fiber = Fiber.new do
      journey.perform_next_step!
    end
    stuck_fiber.resume

    expect(journey).to be_persisted
    expect(journey).to be_performing
    expect(journey.updated_at).to eq(Time.now)

    travel_to Time.now + 2.days
    expect(StepperMotor::Journey.stuck(2.days.ago)).to include(journey)

    expect {
      journey.reload.recover!
    }.not_to raise_error

    journey.reload
    expect(journey).to be_canceled
  end
end
