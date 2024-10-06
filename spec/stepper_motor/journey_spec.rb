require_relative "../spec_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
RSpec.describe "StepperMotor::Journey" do
  include ActiveJob::TestHelper

  before :all do
    establish_test_connection
    run_generator
    run_migrations
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.logger = Logger.new(nil)
  end

  after :all do
    FileUtils.rm_rf(fake_app_root)
  end

  before :each do
    Thread.current[:stepper_motor_side_effects] = {}
  end

  after :each do
    # Remove all jobs that remain in the queue
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  it "allows an empty journey to be defined and performed to completion" do
    class PointlessJourney < StepperMotor::Journey
    end

    journey = PointlessJourney.create!
    journey.perform_next_step!
    expect(journey).to be_finished
  end

  it "allows a journey consisting of one step to be defined and performed to completion" do
    class SingleStepJourney < StepperMotor::Journey
      step :do_thing do
        SideEffects.touch!("do_thing")
      end
    end

    journey = SingleStepJourney.create!
    expect(journey.next_step_to_be_performed_at).not_to be_nil
    journey.perform_next_step!
    expect(journey).to be_finished
    expect(SideEffects).to be_produced("do_thing")
  end

  it "allows a journey consisting of multiple named steps to be defined and performed to completion" do
    step_names = [:step1, :step2, :step3]

    # Use Class.new so that step_names can be passed into the block
    MultiStepJourney = Class.new(StepperMotor::Journey) do
      step_names.each do |step_name|
        step step_name do
          SideEffects.touch!("from_#{step_name}")
        end
      end
    end

    journey = MultiStepJourney.create!
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
    AnonymousStepsJourney = Class.new(StepperMotor::Journey) do
      3.times do |n|
        step do
          SideEffects.touch!("sidefx_#{n}")
        end
      end
    end

    journey = AnonymousStepsJourney.create!
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
    class SomeOtherJourney < StepperMotor::Journey
      step do
        # nothing, but we need to have a step so that the journey doesn't get destroyed immediately after creation
      end
    end

    class CarryingJourney < StepperMotor::Journey
      step :only do
        raise "Incorrect" unless hero.instance_of?(SomeOtherJourney)
      end
    end

    hero = SomeOtherJourney.create!
    journey = CarryingJourney.create!(hero: hero)
    expect {
      journey.perform_next_step!
    }.not_to raise_error
  end

  it "allows a journey where steps are delayed in time using wait:" do
    class TimelyJourney < StepperMotor::Journey
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
    TimelyJourney.create!

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
    class TimelyJourneyUsingAfter < StepperMotor::Journey
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

    TimelyJourneyUsingAfter.create!
    freeze_time
    expect { perform_enqueued_jobs }.to not_have_produced_any_side_effects

    travel 10.hours
    perform_enqueued_jobs
    expect { perform_enqueued_jobs }.to have_produced_side_effects_named("step1")

    travel 4.minutes
    expect { perform_enqueued_jobs }.to not_have_produced_any_side_effects

    travel 1.minutes
    expect { perform_enqueued_jobs }.to have_produced_side_effects_named("step2")
    expect { perform_enqueued_jobs }.to have_produced_side_effects_named("step3")
  end

  it "tracks steps entered and completed using counters" do
    class FailingJourney < StepperMotor::Journey
      step do
        raise "oops"
      end
    end

    class NotFailingJourney < StepperMotor::Journey
      step do
        true # no-op
      end
    end

    failing_journey = FailingJourney.create!
    expect { failing_journey.perform_next_step! }.to raise_error(/oops/)
    expect(failing_journey.steps_entered).to eq(1)
    expect(failing_journey.steps_completed).to eq(0)

    failing_journey.ready!
    expect { failing_journey.perform_next_step! }.to raise_error(/oops/)
    expect(failing_journey.steps_entered).to eq(2)
    expect(failing_journey.steps_completed).to eq(0)

    non_failing_journey = NotFailingJourney.create!
    non_failing_journey.perform_next_step!
    expect(non_failing_journey.steps_entered).to eq(1)
    expect(non_failing_journey.steps_completed).to eq(1)
  end

  it "does not allow invalid values for after: and wait:" do
    expect {
      class MisconfiguredJourney1 < StepperMotor::Journey
        step after: 10.hours do
          # pass
        end

        step after: 5.hours do
          # pass
        end
      end
    }.to raise_error(ArgumentError)

    expect {
      class MisconfiguredJourney2 < StepperMotor::Journey
        step wait: -5.hours do
          # pass
        end
      end
    }.to raise_error(ArgumentError)

    expect {
      class MisconfiguredJourney3 < StepperMotor::Journey
        step after: 5.hours, wait: 2.seconds do
          # pass
        end
      end
    }.to raise_error(ArgumentError)
  end

  it "allows a step to reattempt itself" do
    class DeferringJourney < StepperMotor::Journey
      step do
        reattempt! wait: 5.minutes
        raise "Should never be reached"
      end
    end

    journey = DeferringJourney.create!
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
    class InterruptedJourney < StepperMotor::Journey
      step :step1 do
        SideEffects.touch!("step1_before_cancel")
        cancel!
        SideEffects.touch!("step1_after_cancel")
      end

      step :step2 do
        raise "Should never be reached"
      end
    end

    journey = InterruptedJourney.create!
    expect(journey.next_step_name).to eq("step1")

    perform_enqueued_jobs
    expect(SideEffects).to be_produced("step1_before_cancel")
    expect(SideEffects).not_to be_produced("step1_after_cancel")
    assert_canceled_or_finished(journey)
  end

  it "forbids multiple similar journeys for the same hero at the same time unless allow_multiple is set" do
    class SomeActor < StepperMotor::Journey
    end
    hero = SomeActor.create!

    class ExclusiveJourney < StepperMotor::Journey
      step do
        raise "The step should never be entered as we are not testing the step itself here"
      end
    end

    expect {
      2.times { ExclusiveJourney.create! }
    }.not_to raise_error

    expect {
      2.times { ExclusiveJourney.create!(hero: hero) }
    }.to raise_error(ActiveRecord::RecordNotUnique)

    expect {
      2.times { ExclusiveJourney.create!(hero: hero, allow_multiple: true) }
    }.not_to raise_error
  end

  it "forbids multiple steps with the same name within a journey" do
    expect {
      class RepeatedStepsJourney < StepperMotor::Journey
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
    class RapidlyFinishingJourney < StepperMotor::Journey
      step :one do
        true # no-op
      end
      step :two do
        true # no-op
      end
    end

    journey = RapidlyFinishingJourney.create!
    expect(journey).to be_ready
    journey.perform_next_step!
    expect(journey).to be_ready
    journey.perform_next_step!
    expect(journey).to be_finished
  end

  it "does not enter next step on a finished journey" do
    class NearInstantJourney < StepperMotor::Journey
      step :one do
        finished!
      end

      step :two do
        raise "Should never be reache"
      end
    end

    journey = NearInstantJourney.create!
    expect(journey).to be_ready
    journey.perform_next_step!
    expect(journey).to be_finished

    expect { journey.perform_next_step! }.not_to raise_error
  end

  it "raises an exception if a step changes the journey but does not save it" do
    class MutatingJourney < StepperMotor::Journey
      step :one do
        self.state = "canceled"
      end
    end

    journey = MutatingJourney.create!
    expect {
      journey.perform_next_step!
    }.to raise_error(StepperMotor::JourneyNotPersisted)
  end

  it "resets the instance variables after performing a step" do
    class SelfResettingJourney < StepperMotor::Journey
      step :one do
        raise unless @current_step_definition
      end

      step :two do
        @reattempt_after = 2.minutes
      end
    end

    journey = SelfResettingJourney.create!
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
