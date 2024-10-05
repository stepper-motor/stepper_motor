require_relative "../spec_helper"

# rubocop:disable Lint/ConstantDefinitionInBlock
RSpec.describe "StepperMotor::Journey" do
  include ActiveJob::TestHelper

  before :all do
    establish_test_connection
    run_generator
    run_migrations
    ActiveJob::Base.queue_adapter = :test
  end

  after :all do
    FileUtils.rm_rf(fake_app_root)
  end

  before :each do
    Thread.current[:stepper_motor_side_effects] = {}
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
        Thread.current[:stepper_motor_side_effects]["do_thing_output.txt"] = self.class.to_s
      end
    end

    journey = SingleStepJourney.create!
    expect(journey.next_step_to_be_performed_at).not_to be_nil
    journey.perform_next_step!
    expect(journey).to be_finished

    expect(read_side_effect("do_thing_output.txt")).to eq("StepperMotorTest::SingleStepJourney")
  end

  it "allows a journey consisting of multiple named steps to be defined and performed to completion" do
    step_names = [:step1, :step2, :step3]

    # Use Class.new so that step_names can be passed into the block
    MultiStepJourney = Class.new(StepperMotor::Journey) do
      step_names.each do |step_name|
        step step_name do
          Thread.current[:stepper_motor_side_effects]["multi_step_#{step_name}.txt"] = self.class.to_s
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

    step_names.each do |step_name|
      step_output_filename = "multi_step_#{step_name}.txt"
      expect(read_side_effect(step_output_filename)).to eq("StepperMotorTest::MultiStepJourney")
    end
  end

  it "allows a journey consisting of multiple anonymous steps to be defined and performed to completion" do
    AnonymousStepsJourney = Class.new(StepperMotor::Journey) do
      3.times do |n|
        step do
          Thread.current[:stepper_motor_side_effects]["multi_step_step_#{n}.txt"] = self.class.to_s
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

    3.times do |n|
      step_output_filename = "multi_step_step_#{n}.txt"
      expect(read_side_effect(step_output_filename)).to eq("StepperMotorTest::AnonymousStepsJourney")
    end
  end

  it "allows an arbitrary ActiveRecord to be attached as the hero" do
    class SomeOtherJourney < StepperMotor::Journey
      step do
        # nothing, but we need to have a step so that the journey doesn't get destroyed immediately after creation
      end
    end

    class CarryingJourney < StepperMotor::Journey
      step :only do
        Thread.current[:stepper_motor_side_effects]["only_step_output.txt"] = hero.class.to_s
      end
    end

    hero = SomeOtherJourney.create!
    journey = CarryingJourney.create!(hero:)
    journey.perform_next_step!

    expect(read_side_effect("only_step_output.txt")).to eq("StepperMotorTest::SomeOtherJourney")
  end

  it "allows a journey where steps are delayed in time using wait:" do
    class TimelyJourney < StepperMotor::Journey
      step wait: 10.hours do
        Thread.current[:stepper_motor_side_effects]["after_10_hours.txt"] = "t"
      end

      step wait: 5.minutes do
        Thread.current[:stepper_motor_side_effects]["after_5_minutes.txt"] = "t"
      end

      step do
        Thread.current[:stepper_motor_side_effects]["final_nowait.txt"] = "t"
      end
    end

    freeze_time
    TimelyJourney.create!
    perform_enqueued_jobs
    refute_side_effect("after_10_hours.txt")

    travel 10.hours
    perform_enqueued_jobs
    assert_side_effect("after_10_hours.txt")

    travel 4.minutes
    perform_enqueued_jobs
    refute_side_effect("after_5_minutes.txt")

    travel 1.minutes
    perform_enqueued_jobs
    assert_side_effect("after_5_minutes.txt")

    perform_enqueued_jobs
    assert_side_effect("final_nowait.txt")
  end

  it "allows a journey where steps are delayed in time using after:" do
    class TimelyJourneyUsingAfter < StepperMotor::Journey
      step after: 10.hours do
        Thread.current[:stepper_motor_side_effects]["after_10_hours.txt"] = "t"
      end

      step after: 605.minutes do
        Thread.current[:stepper_motor_side_effects]["after_5_minutes.txt"] = "t"
      end

      step do
        Thread.current[:stepper_motor_side_effects]["final_nowait.txt"] = "t"
      end
    end

    freeze_time
    TimelyJourneyUsingAfter.create!
    perform_enqueued_jobs
    refute_side_effect("after_10_hours.txt")

    travel 10.hours
    perform_enqueued_jobs
    assert_side_effect("after_10_hours.txt")

    travel 4.minutes
    perform_enqueued_jobs
    refute_side_effect("after_5_minutes.txt")

    travel 1.minutes
    perform_enqueued_jobs
    assert_side_effect("after_5_minutes.txt")

    perform_enqueued_jobs
    assert_side_effect("final_nowait.txt")
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
        Thread.current[:stepper_motor_side_effects]["step1_before_bailout.txt"] = self.class.to_s
        cancel!
        Thread.current[:stepper_motor_side_effects]["step1_after_bailout.txt"] = self.class.to_s
      end

      step :step2 do
        raise "Should never be reached"
      end
    end

    journey = InterruptedJourney.create!
    expect(journey.next_step_name).to eq("step1")

    perform_enqueued_jobs
    assert_canceled_or_finished(journey)

    assert_side_effect "step1_before_bailout.txt"
    refute_side_effect "step1_after_bailout.txt"
  end

  xit "forbids multiple similar journeys for the same hero at the same time unless allow_multiple is set" do
    class SomeActor < StepperMotor::Journey
    end
    hero = SomeActor.create!

    class ExclusiveJourney < StepperMotor::Journey
      step do
        raise "We are not testing this here"
      end
    end

    expect {
      2.times { ExclusiveJourney.create! }
    }.not_to raise_error

    expect {
      2.times { ExclusiveJourney.create!(hero:) }
    }.to raise_error(ActiveRecord::RecordNotUnique)

    expect {
      2.times { ExclusiveJourney.create!(hero:, allow_multiple: true) }
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

    expect { journey.perform_next_step! }.not_to raise_rrror
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
    expect(model.state).to be_in("canceled", "finished")
  end

  def read_side_effect(name)
    assert_side_effect(name)
    Thread.current[:stepper_motor_side_effects][name]
  end

  def assert_side_effect(name)
    expect(Thread.current[:stepper_motor_side_effects]).to have_key(name), "A side effect named #{name.inspect} should not have been produced, but was"
  end

  def refute_side_effect(name)
    expect(Thread.current[:stepper_motor_side_effects]).not_to have_key(name), "A side effect named #{name.inspect} should not have been produced, but was"
  end
end
# rubocop:enable Lint/ConstantDefinitionInBlock
