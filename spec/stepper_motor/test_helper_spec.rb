# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "StepperMotor::TestHelper" do
  include SideEffects::SpecHelper
  include StepperMotor::TestHelper

  before do
    establish_test_connection
    run_generator
    run_migrations
  end

  def speedy_journey_class
    create_journey_subclass do
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
  end

  it "speedruns the journey despite waits being configured" do
    journey = speedy_journey_class.create!
    expect(journey).to be_ready

    expect {
      speedrun_journey(journey)
    }.to have_produced_side_effects_named("step_1", "step_2", "step_3")
  end

  it "is able to perform a single step forcibly" do
    journey = speedy_journey_class.create!
    expect(journey).to be_ready

    expect {
      immediately_perform_single_step(journey, :step_2)
    }.to have_produced_side_effects_named("step_2")
  end
end
