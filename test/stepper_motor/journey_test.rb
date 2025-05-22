# frozen_string_literal: true

require "test_helper"

class JourneyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SideEffects::TestHelper

  test "allows an empty journey to be defined and performed to completion" do
    pointless_class = create_journey_subclass
    journey = pointless_class.create!
    journey.perform_next_step!
    assert journey.finished?
  end

  test "allows a journey consisting of one step to be defined and performed to completion" do
    single_step_class = create_journey_subclass do
      step :do_thing do
        SideEffects.touch!("do_thing")
      end
    end

    journey = single_step_class.create!
    assert_not_nil journey.next_step_to_be_performed_at
    journey.perform_next_step!
    assert journey.finished?
    assert SideEffects.produced?("do_thing")
  end

  test "allows a journey consisting of multiple named steps to be defined and performed to completion" do
    multi_step_journey_class = create_journey_subclass do
      [:step1, :step2, :step3].each do |step_name|
        step step_name do
          SideEffects.touch!("from_#{step_name}")
        end
      end
    end

    journey = multi_step_journey_class.create!
    assert_equal "step1", journey.next_step_name

    journey.perform_next_step!
    assert_equal "step2", journey.next_step_name
    assert_equal "step1", journey.previous_step_name

    journey.perform_next_step!
    assert_equal "step3", journey.next_step_name
    assert_equal "step2", journey.previous_step_name

    journey.perform_next_step!
    assert journey.finished?
    assert_nil journey.next_step_name
    assert_equal "step3", journey.previous_step_name

    assert SideEffects.produced?("from_step1")
    assert SideEffects.produced?("from_step2")
    assert SideEffects.produced?("from_step3")
  end

  test "allows a journey consisting of multiple anonymous steps to be defined and performed to completion" do
    anonymous_steps_class = create_journey_subclass do
      3.times do |n|
        step do
          SideEffects.touch!("sidefx_#{n}")
        end
      end
    end

    journey = anonymous_steps_class.create!
    assert_equal "step_1", journey.next_step_name

    journey.perform_next_step!
    assert_equal "step_2", journey.next_step_name
    assert_equal "step_1", journey.previous_step_name

    journey.perform_next_step!
    assert_equal "step_3", journey.next_step_name
    assert_equal "step_2", journey.previous_step_name

    journey.perform_next_step!
    assert journey.finished?
    assert_nil journey.next_step_name
    assert_equal "step_3", journey.previous_step_name

    assert SideEffects.produced?("sidefx_0")
    assert SideEffects.produced?("sidefx_1")
    assert SideEffects.produced?("sidefx_2")
  end

  test "allows an arbitrary ActiveRecord to be attached as the hero" do
    carried_journey_class = create_journey_subclass
    carrier_journey_class = create_journey_subclass do
      step :only do
        raise "Incorrect" unless hero.instance_of?(carried_journey_class)
      end
    end

    hero = carried_journey_class.create!
    journey = carrier_journey_class.create!(hero: hero)
    assert_nothing_raised do
      journey.perform_next_step!
    end
  end

  test "allows a journey where steps are delayed in time using wait:" do
    timely_journey_class = create_journey_subclass do
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

    assert_no_side_effects do
      perform_enqueued_jobs
    end

    travel 10.hours
    assert_produced_side_effects "after_10_hours.txt" do
      perform_enqueued_jobs
    end

    travel 4.minutes
    assert_no_side_effects do
      perform_enqueued_jobs
    end

    travel 1.minutes
    assert_produced_side_effects "after_5_minutes.txt" do
      perform_enqueued_jobs
    end

    assert_produced_side_effects "final_nowait.txt" do
      perform_enqueued_jobs
    end
  end

  test "allows a journey where steps are delayed in time using after:" do
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

    assert_no_side_effects do
      perform_enqueued_jobs
    end

    travel_to(timely_journey.next_step_to_be_performed_at + 1.second)
    assert_produced_side_effects "step1" do
      perform_enqueued_jobs
    end

    travel(4.minutes)
    assert_no_side_effects do
      perform_enqueued_jobs
    end

    travel(1.minutes + 1.second)
    assert_produced_side_effects "step2" do
      perform_enqueued_jobs
    end
    assert_produced_side_effects "step3" do
      perform_enqueued_jobs
    end
    assert_empty enqueued_jobs # Journey ended
  end

  test "tracks steps entered and completed using counters" do
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
    assert_raises(RuntimeError) { failing_journey.perform_next_step! }
    assert_equal 1, failing_journey.steps_entered
    assert_equal 0, failing_journey.steps_completed

    failing_journey.ready!
    assert_raises(RuntimeError) { failing_journey.perform_next_step! }
    assert_equal 2, failing_journey.steps_entered
    assert_equal 0, failing_journey.steps_completed

    non_failing_journey = not_failing.create!
    non_failing_journey.perform_next_step!
    assert_equal 1, non_failing_journey.steps_entered
    assert_equal 1, non_failing_journey.steps_completed
  end

  test "does not allow invalid values for after: and wait:" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step after: 10.hours do
          # pass
        end

        step after: 5.hours do
          # pass
        end
      end
    end

    assert_raises(ArgumentError) do
      create_journey_subclass do
        step wait: -5.hours do
          # pass
        end
      end
    end

    assert_raises(ArgumentError) do
      create_journey_subclass do
        step after: 5.hours, wait: 2.seconds do
          # pass
        end
      end
    end
  end

  test "allows a step to reattempt itself" do
    deferring = create_journey_subclass do
      step do
        reattempt! wait: 5.minutes
        raise "Should never be reached"
      end
    end

    journey = deferring.create!
    perform_enqueued_jobs

    journey.reload
    assert_equal "step_1", journey.previous_step_name
    assert_equal "step_1", journey.next_step_name
    assert_in_delta Time.current + 5.minutes, journey.next_step_to_be_performed_at, 1.second

    travel 5.minutes + 1.second
    perform_enqueued_jobs

    journey.reload
    assert_equal "step_1", journey.previous_step_name
    assert_equal "step_1", journey.next_step_name
    assert_in_delta Time.current + 5.minutes, journey.next_step_to_be_performed_at, 1.second
  end

  test "allows a journey consisting of multiple steps where the first step bails out to be defined and performed to the point of cancellation" do
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
    assert_equal "step1", journey.next_step_name

    perform_enqueued_jobs
    assert SideEffects.produced?("step1_before_cancel")
    assert_not SideEffects.produced?("step1_after_cancel")
    assert_canceled_or_finished(journey)
  end

  test "forbids multiple similar journeys for the same hero at the same time unless allow_multiple is set" do
    actor_class = create_journey_subclass
    hero = actor_class.create!

    exclusive_journey_class = create_journey_subclass do
      step do
        raise "The step should never be entered as we are not testing the step itself here"
      end
    end

    assert_nothing_raised do
      2.times { exclusive_journey_class.create! }
    end

    assert_raises(ActiveRecord::RecordNotUnique) do
      2.times { exclusive_journey_class.create!(hero: hero) }
    end

    assert_nothing_raised do
      2.times { exclusive_journey_class.create!(hero: hero, allow_multiple: true) }
    end
  end

  test "forbids multiple steps with the same name within a journey" do
    assert_raises(ArgumentError) do
      create_journey_subclass do
        step :foo do
          true
        end

        step "foo" do
          true
        end
      end
    end
  end

  test "finishes the journey after perform_next_step" do
    rapid = create_journey_subclass do
      step :one do
        true # no-op
      end
      step :two do
        true # no-op
      end
    end

    journey = rapid.create!
    assert journey.ready?
    journey.perform_next_step!
    assert journey.ready?
    journey.perform_next_step!
    assert journey.finished?
  end

  test "does not enter next step on a finished journey" do
    near_instant = create_journey_subclass do
      step :one do
        finished!
      end

      step :two do
        raise "Should never be reached"
      end
    end

    journey = near_instant.create!
    assert journey.ready?
    journey.perform_next_step!
    assert journey.finished?

    assert_nothing_raised do
      journey.perform_next_step!
    end
  end

  test "raises an exception if a step changes the journey but does not save it" do
    mutating = create_journey_subclass do
      step :one do
        self.state = "canceled"
      end
    end

    journey = mutating.create!
    assert_raises(StepperMotor::JourneyNotPersisted) do
      journey.perform_next_step!
    end
  end

  test "resets the instance variables after performing a step" do
    self_resetting = create_journey_subclass do
      step :one do
        raise unless @current_step_definition
      end

      step :two do
        @reattempt_after = 2.minutes
      end
    end

    journey = self_resetting.create!
    assert_nothing_raised do
      journey.perform_next_step!
    end
    assert_nil journey.instance_variable_get(:@current_step_definition)

    assert_nothing_raised do
      journey.perform_next_step!
    end
    assert_nil journey.instance_variable_get(:@current_step_definition)
    assert_nil journey.instance_variable_get(:@reattempt_after)
  end

  test "does not perform the step if the idempotency key passed does not match the one stored" do
    journey_class = create_journey_subclass do
      step do
        raise "Should not happen"
      end
    end

    journey = journey_class.create!

    assert_predicate journey, :ready?
    assert journey.idempotency_key
    assert_nothing_raised do
      journey.perform_next_step!(idempotency_key: journey.idempotency_key + "n")
    end
    assert_predicate journey, :ready?
  end

  test "does perform the step if the idempotency key is set but not passed to perform_next_step!" do
    journey_class = create_journey_subclass do
      step do
        SideEffects.touch! :with_ik
      end
    end

    journey = journey_class.create!

    assert_predicate journey, :ready?
    assert journey.idempotency_key
    assert_produced_side_effects(:with_ik) do
      journey.perform_next_step!
    end
    assert_predicate journey, :finished?
  end

  test "updates the idempotency key when a step gets reattempted" do
    some_journey_class = create_journey_subclass do
      step :one do
        reattempt! wait: 2.minutes
      end
    end
    freeze_time

    journey = some_journey_class.create!

    assert_equal "one", journey.next_step_name
    assert journey.idempotency_key.present? # Since it was scheduled for the initial step
    previous_idempotency_key = journey.idempotency_key

    perform_enqueued_jobs # Should be reattempted

    journey.reload

    assert_equal "one", journey.next_step_name
    assert journey.idempotency_key
    refute_equal journey.idempotency_key, previous_idempotency_key
  end

  private

  def assert_canceled_or_finished(model)
    model.reload
    assert_includes ["canceled", "finished"], model.state
  end

  def assert_produced_side_effects(name)
    yield
    assert SideEffects.produced?(name)
  end
end
