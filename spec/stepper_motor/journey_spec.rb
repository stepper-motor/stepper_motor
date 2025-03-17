# frozen_string_literal: true

require_relative "../spec_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
RSpec.describe "StepperMotor::Journey" do
  include ActiveJob::TestHelper

  it "allows an empty journey to be defined and performed to completion" do
    pointless_class = create_journey_subclass
    journey = pointless_class.create!
    journey.perform_next_step!
    expect(journey).to be_finished
  end

  it "allows a journey consisting of one step to be defined and performed to completion" do
    single_step_class = create_journey_subclass do
      step :do_thing do
        SideEffects.touch!("do_thing")
      end
    end

    journey = single_step_class.create!
    expect(journey.next_step_to_be_performed_at).not_to be_nil
    journey.perform_next_step!
    expect(journey).to be_finished
    expect(SideEffects).to be_produced("do_thing")
  end

  it "allows a journey consisting of multiple named steps to be defined and performed to completion" do
    step_names = [:step1, :step2, :step3]

    multi_step_journey_class = create_journey_subclass do
      [:step1, :step2, :step3].each do |step_name|
        step step_name do
          SideEffects.touch!("from_#{step_name}")
        end
      end
    end

    journey = multi_step_journey_class.create!
    expect(journey.next_step_name).to eq("step1")

    journey.perform_next_step!
    expect(journey.next_step_name).to eq("step2")
    expect(journey.previous_step_name).to eq("step1")

    journey.perform_next_step!
    expect(journey.next_step_name).to eq("step3")
    expect(journey.previous_step_name).to eq("step2")

    journey.perform_next_step!
    expect(journey).to be_finished
    expect(journey.next_step_name).to be_nil
    expect(journey.previous_step_name).to eq("step3")

    expect(SideEffects).to be_produced("from_step1")
    expect(SideEffects).to be_produced("from_step2")
    expect(SideEffects).to be_produced("from_step3")
  end

  it "allows a journey consisting of multiple anonymous steps to be defined and performed to completion" do
    anonymous_steps_class = create_journey_subclass do
      3.times do |n|
        step do
          SideEffects.touch!("sidefx_#{n}")
        end
      end
    end

    journey = anonymous_steps_class.create!
    expect(journey.next_step_name).to eq("step_1")

    journey.perform_next_step!
    expect(journey.next_step_name).to eq("step_2")
    expect(journey.previous_step_name).to eq("step_1")

    journey.perform_next_step!
    expect(journey.next_step_name).to eq("step_3")
    expect(journey.previous_step_name).to eq("step_2")

    journey.perform_next_step!
    expect(journey).to be_finished
    expect(journey.next_step_name).to be_nil
    expect(journey.previous_step_name).to eq("step_3")

    expect(SideEffects).to be_produced("sidefx_0")
    expect(SideEffects).to be_produced("sidefx_1")
    expect(SideEffects).to be_produced("sidefx_2")
  end

  it "allows an arbitrary ActiveRecord to be attached as the hero" do
    carried_journey_class = create_journey_subclass
    carrier_journey_class = create_journey_subclass do
      step :only do
        raise "Incorrect" unless hero.instance_of?(carried_journey_class)
      end
    end

    hero = carried_journey_class.create!
    journey = carrier_journey_class.create!(hero: hero)
    expect {
      journey.perform_next_step!
    }.not_to raise_error
  end

  it "allows a journey where steps are delayed in time using wait:" do
    timely_journey_class = carrier_journey_class = create_journey_subclass do
      step wait: 10.hours do
        SideEffects.touch! "after_10_hours.txt"
      end

      step wait: 5.minutes do
        SideEffects.touch! "after_5_minutes.txt"
      end

      step do
        SideEffects.touch! "final_nowait.txt"
      end
    end

    freeze_time
    timely_journey_class.create!

    expect {
      perform_enqueued_jobs
    }.to not_have_produced_any_side_effects

    travel 10.hours
    expect {
      perform_enqueued_jobs
    }.to have_produced_side_effects_named("after_10_hours.txt")

    travel 4.minutes
    expect {
      perform_enqueued_jobs
    }.to not_have_produced_any_side_effects

    travel 1.minutes
    expect {
      perform_enqueued_jobs
    }.to have_produced_side_effects_named("after_5_minutes.txt")

    expect {
      perform_enqueued_jobs
    }.to have_produced_side_effects_named("final_nowait.txt")
  end

  it "allows a journey where steps are delayed in time using after:" do
    journey_class = create_journey_subclass do
      step after: 10.hours do
        SideEffects.touch! "step1"
      end

      step after: 605.minutes do
        SideEffects.touch! "step2"
      end

      step do
        SideEffects.touch! "step3"
      end
    end

    timely_journey = journey_class.create!
    freeze_time

    # Note that the "perform_enqueued_jobs" helper method performs the job even if
    # its "scheduled_at" lies in the future. Presumably this is done so that testing is
    # easier to do, but we check the time the journey was set to perform the next step at
    # - and therefore a job which runs too early will produce another job that replaces it.
    expect { perform_enqueued_jobs }.to not_have_produced_any_side_effects

    travel_to(timely_journey.next_step_to_be_performed_at + 1.second)
    expect { perform_enqueued_jobs }.to have_produced_side_effects_named("step1")

    travel(4.minutes)
    expect { perform_enqueued_jobs }.to not_have_produced_any_side_effects

    travel(1.minutes + 1.second)
    expect { perform_enqueued_jobs }.to have_produced_side_effects_named("step2")
    expect { perform_enqueued_jobs }.to have_produced_side_effects_named("step3")
    expect(enqueued_jobs).to be_empty # Journey ended
  end

  it "tracks steps entered and completed using counters" do
    failing = create_journey_subclass do
      step do
        raise "oops"
      end
    end

    not_failing = create_journey_subclass do
      step do
        true # no-op
      end
    end

    failing_journey = failing.create!
    expect { failing_journey.perform_next_step! }.to raise_error(/oops/)
    expect(failing_journey.steps_entered).to eq(1)
    expect(failing_journey.steps_completed).to eq(0)

    failing_journey.ready!
    expect { failing_journey.perform_next_step! }.to raise_error(/oops/)
    expect(failing_journey.steps_entered).to eq(2)
    expect(failing_journey.steps_completed).to eq(0)

    non_failing_journey = not_failing.create!
    non_failing_journey.perform_next_step!
    expect(non_failing_journey.steps_entered).to eq(1)
    expect(non_failing_journey.steps_completed).to eq(1)
  end

  it "does not allow invalid values for after: and wait:" do
    expect {
      create_journey_subclass do
        step after: 10.hours do
          # pass
        end

        step after: 5.hours do
          # pass
        end
      end
    }.to raise_error(ArgumentError)

    expect {
      create_journey_subclass do
        step wait: -5.hours do
          # pass
        end
      end
    }.to raise_error(ArgumentError)

    expect {
      create_journey_subclass do
        step after: 5.hours, wait: 2.seconds do
          # pass
        end
      end
    }.to raise_error(ArgumentError)
  end

  it "allows a step to reattempt itself" do
    deferring = create_journey_subclass do
      step do
        reattempt! wait: 5.minutes
        raise "Should never be reached"
      end
    end

    journey = deferring.create!
    perform_enqueued_jobs

    journey.reload
    expect(journey.previous_step_name).to eq("step_1")
    expect(journey.next_step_name).to eq("step_1")
    expect(journey.next_step_to_be_performed_at).to be_within(1.second).of(Time.current + 5.minutes)

    travel 5.minutes + 1.second
    perform_enqueued_jobs

    journey.reload
    expect(journey.previous_step_name).to eq("step_1")
    expect(journey.next_step_name).to eq("step_1")
    expect(journey.next_step_to_be_performed_at).to be_within(1.second).of(Time.current + 5.minutes)
  end

  it "allows a journey consisting of multiple steps where the first step bails out to be defined and performed to the point of cancellation" do
    interrupting = create_journey_subclass do
      step :step1 do
        SideEffects.touch!("step1_before_cancel")
        cancel!
        SideEffects.touch!("step1_after_cancel")
      end

      step :step2 do
        raise "Should never be reached"
      end
    end

    journey = interrupting.create!
    expect(journey.next_step_name).to eq("step1")

    perform_enqueued_jobs
    expect(SideEffects).to be_produced("step1_before_cancel")
    expect(SideEffects).not_to be_produced("step1_after_cancel")
    assert_canceled_or_finished(journey)
  end

  it "forbids multiple similar journeys for the same hero at the same time unless allow_multiple is set" do
    actor_class = create_journey_subclass
    hero = actor_class.create!

    exclusive_journey_class = create_journey_subclass do
      step do
        raise "The step should never be entered as we are not testing the step itself here"
      end
    end

    expect {
      2.times { exclusive_journey_class.create! }
    }.not_to raise_error

    expect {
      2.times { exclusive_journey_class.create!(hero: hero) }
    }.to raise_error(ActiveRecord::RecordNotUnique)

    expect {
      2.times { exclusive_journey_class.create!(hero: hero, allow_multiple: true) }
    }.not_to raise_error
  end

  it "forbids multiple steps with the same name within a journey" do
    expect {
      create_journey_subclass do
        step :foo do
          true
        end

        step "foo" do
          true
        end
      end
    }.to raise_error(ArgumentError)
  end

  it "finishes the journey after perform_next_step" do
    rapid = create_journey_subclass do
      step :one do
        true # no-op
      end
      step :two do
        true # no-op
      end
    end

    journey = rapid.create!
    expect(journey).to be_ready
    journey.perform_next_step!
    expect(journey).to be_ready
    journey.perform_next_step!
    expect(journey).to be_finished
  end

  it "does not enter next step on a finished journey" do
    near_instant = create_journey_subclass do
      step :one do
        finished!
      end

      step :two do
        raise "Should never be reache"
      end
    end

    journey = near_instant.create!
    expect(journey).to be_ready
    journey.perform_next_step!
    expect(journey).to be_finished

    expect { journey.perform_next_step! }.not_to raise_error
  end

  it "raises an exception if a step changes the journey but does not save it" do
    mutating = create_journey_subclass do
      step :one do
        self.state = "canceled"
      end
    end

    journey = mutating.create!
    expect {
      journey.perform_next_step!
    }.to raise_error(StepperMotor::JourneyNotPersisted)
  end

  it "resets the instance variables after performing a step" do
    self_resetting = create_journey_subclass do
      step :one do
        raise unless @current_step_definition
      end

      step :two do
        @reattempt_after = 2.minutes
      end
    end

    journey = self_resetting.create!
    expect { journey.perform_next_step! }.not_to raise_error
    expect(journey.instance_variable_get(:@current_step_definition)).to be_nil

    expect { journey.perform_next_step! }.not_to raise_error
    expect(journey.instance_variable_get(:@current_step_definition)).to be_nil
    expect(journey.instance_variable_get(:@reattempt_after)).to be_nil
  end

  def assert_canceled_or_finished(model)
    model.reload
    expect(model.state).to be_in(["canceled", "finished"])
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
