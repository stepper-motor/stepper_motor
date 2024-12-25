require_relative "../spec_helper"

RSpec.describe "StepperMotor::TestHelper" do
  include SideEffects::SpecHelper
  include StepperMotor::TestHelper

  before do
    establish_test_connection
    run_generator
    run_migrations
  end

  class SpeedyJourney < StepperMotor::Journey
    step :step_1, wait: 40.minutes do
      SideEffects.touch!("step_1")
    end

    step :step_2, wait: 2.days do
      SideEffects.touch!("step_2")
    end

    step do
      SideEffects.touch!("step_3")
    end
  end

  it "speedruns the journey despite waits being configured" do
    journey = SpeedyJourney.create!
    expect(journey).to be_ready

    expect {
      speedrun_stepper_motor_journey(journey)
    }.to have_produced_side_effects_named("step_1", "step_2", "step_3")
  end
end