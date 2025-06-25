# typed: strong
# StepperMotor is a module for building multi-step flows where steps are sequential and only
# ever progress forward. The building block of StepperMotor is StepperMotor::Journey
module StepperMotor
  VERSION = T.let("0.1.18", T.untyped)
  PerformStepJobV2 = T.let(StepperMotor::PerformStepJob, T.untyped)
  RecoverStuckJourneysJobV1 = T.let(StepperMotor::RecoverStuckJourneysJob, T.untyped)

  # sord omit - no YARD return type given, using untyped
  # Extends the BaseJob of the library with any additional options
  sig { params(blk: T.untyped).returns(T.untyped) }
  def self.extend_base_job(&blk); end

  class Error < StandardError
  end

  class JourneyNotPersisted < StepperMotor::Error
  end

  class StepConfigurationError < ArgumentError
  end

  # Describes a step in a journey. These objects get stored inside the `step_definitions`
  # array of the Journey subclass. When the step gets performed, the block passed to the
  # constructor will be instance_exec'd with the Journey model being the context
  class Step
    # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
    # Creates a new step definition
    # 
    # _@param_ `name` — the name of the Step
    # 
    # _@param_ `wait` — the amount of time to wait before entering the step
    # 
    # _@param_ `on_exception` — the action to take if an exception occurs when performing the step. The possible values are: * `:cancel!` - cancels the Journey and re-raises the exception. The Journey will be persisted before re-raising. * `:reattempt!` - reattempts the Journey and re-raises the exception. The Journey will be persisted before re-raising. * `:pause!` - pauses the Journey and re-raises the exception. The Journey will be persisted before re-raising. * `:skip!` - skips the current step and proceeds to the next step, or finishes the journey if it's the last step.
    # 
    # _@param_ `skip_if` — condition to check before performing the step. If a boolean is provided, it will be used directly. If nil is provided, it will be treated as false. If a symbol is provided, it will call the method on the Journey. If a block is provided, it will be executed with the Journey as context. The step will only be performed if the condition returns a truthy value.
    sig do
      params(
        name: T.any(String, Symbol),
        on_exception: Symbol,
        wait: T.any(Numeric, ActiveSupport::Duration),
        skip_if: T.any(TrueClass, FalseClass, NilClass, Symbol, Proc),
        step_block: T.untyped
      ).void
    end
    def initialize(name:, on_exception: :pause!, wait: 0, skip_if: false, &step_block); end

    # Checks if the step should be skipped based on the skip_if condition
    # 
    # _@param_ `journey` — the journey to check the condition for
    # 
    # _@return_ — true if the step should be skipped, false otherwise
    sig { params(journey: StepperMotor::Journey).returns(T::Boolean) }
    def should_skip?(journey); end

    # Performs the step on the passed Journey, wrapping the step with the required context.
    # 
    # _@param_ `journey` — the journey to perform the step in. If a `step_block` is passed in, it is going to be executed in the context of the journey using `instance_exec`. If only the name of the step has been provided, an accordingly named public method on the journey will be called
    # 
    # _@return_ — void
    sig { params(journey: StepperMotor::Journey).returns(T.untyped) }
    def perform_in_context_of(journey); end

    # _@return_ — the name of the step or method to call on the Journey
    sig { returns(String) }
    attr_reader :name

    # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
    # _@return_ — how long to wait before performing the step
    sig { returns(T.any(Numeric, ActiveSupport::Duration)) }
    attr_reader :wait

    class MissingDefinition < NoMethodError
    end
  end

  # A Journey is the main building block of StepperMotor. You create a journey to guide a particular model
  # ("hero") through a sequence of steps. Any of your model can be the hero and have multiple Journeys. To create
  # your own Journey, subclass the `StepperMotor::Journey` class and define your steps. For example, a drip mail
  # campaign can look like this:
  # 
  # 
  #     class ResubscribeCampaign < StepperMotor::Journey
  #       step do
  #         ReinviteMailer.with(recipient: hero).deliver_later
  #       end
  # 
  #       step wait: 3.days do
  #         cancel! if hero.active?
  #         ReinviteMailer.with(recipient: hero).deliver_later
  #       end
  # 
  #       step wait: 3.days do
  #         cancel! if hero.active?
  #         ReinviteMailer.with(recipient: hero).deliver_later
  #       end
  # 
  #       step wait: 3.days do
  #         cancel! if hero.active?
  #         hero.close_account!
  #       end
  #     end
  # 
  # Creating a record for the Journey (just using `create!`) will instantly send your hero on their way:
  # 
  #     ResubscribeCampaign.create!(hero: current_account)
  # 
  # To stop the journey forcibly, delete it from your database - or call `cancel!` within any of the steps.
  class Journey < ActiveRecord::Base
    include StepperMotor::Journey::FlowControl
    include StepperMotor::Journey::Recovery
    STATES = T.let(%w[ready paused performing canceled finished], T.untyped)

    # sord omit - no YARD return type given, using untyped
    # Alias for the class attribute, for brevity
    # 
    # _@see_ `Journey.step_definitions`
    sig { returns(T.untyped) }
    def step_definitions; end

    # _@return_ — the cancel_if conditions defined for this journey class
    sig { returns(T::Array[StepperMotor::Conditional]) }
    def cancel_if_conditions; end

    # sord duck - #to_f looks like a duck type, replacing with untyped
    # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
    # sord duck - #to_f looks like a duck type, replacing with untyped
    # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
    # Defines a step in the journey.
    # Steps are stacked top to bottom and get performed in sequence.
    # 
    # _@param_ `name` — the name of the step. If none is provided, a name will be automatically generated based on the position of the step in the list of `step_definitions`. The name can also be used to call a method on the `Journey` instead of calling the provided block.
    # 
    # _@param_ `wait` — the amount of time this step should wait before getting performed. When the journey gets scheduled, the triggering job is going to be delayed by this amount of time, and the `next_step_to_be_performed_at` attribute will be set to the current time plus the wait duration. Mutually exclusive with `after:`
    # 
    # _@param_ `after` — the amount of time this step should wait before getting performed including all the previous waits. This allows you to set the wait time based on the time after the journey started, as opposed to when the previous step has completed. When the journey gets scheduled, the triggering job is going to be delayed by this amount of time _minus the `wait` values of the preceding steps, and the `next_step_to_be_performed_at` attribute will be set to the current time. The `after` value gets converted into the `wait` value and passed to the step definition. Mutually exclusive with `wait:`.
    # 
    # _@param_ `before_step` — the name of the step before which this step should be inserted. This allows you to control the order of steps by inserting a step before a specific existing step. The step name can be provided as a string or symbol. Mutually exclusive with `after_step:`.
    # 
    # _@param_ `after_step` — the name of the step after which this step should be inserted. This allows you to control the order of steps by inserting a step after a specific existing step. The step name can be provided as a string or symbol. Mutually exclusive with `before_step:`.
    # 
    # _@param_ `on_exception` — See {StepperMotor::Step#on_exception}
    # 
    # _@param_ `skip_if` — condition to check before performing the step. If a symbol is provided, it will call the method on the Journey. If a block is provided, it will be executed with the Journey as context. The step will be skipped if the condition returns a truthy value.
    # 
    # _@param_ `if` — condition to check before performing the step. If a symbol is provided, it will call the method on the Journey. If a block is provided, it will be executed with the Journey as context. The step will be performed if the condition returns a truthy value. and skipped otherwise. Inverse of `skip_if`.
    # 
    # _@param_ `additional_step_definition_options` — Any remaining options get passed to `StepperMotor::Step.new` as keyword arguments.
    # 
    # _@return_ — the step definition that has been created
    sig do
      params(
        name: T.nilable(String),
        wait: T.nilable(T.any(Float, T.untyped, ActiveSupport::Duration)),
        after: T.nilable(T.any(Float, T.untyped, ActiveSupport::Duration)),
        before_step: T.nilable(T.any(String, Symbol)),
        after_step: T.nilable(T.any(String, Symbol)),
        additional_step_definition_options: T::Hash[T.untyped, T.untyped],
        blk: T.untyped
      ).returns(StepperMotor::Step)
    end
    def self.step(name = nil, wait: nil, after: nil, before_step: nil, after_step: nil, **additional_step_definition_options, &blk); end

    # sord warn - "StepperMotor::Step?" does not appear to be a type
    # Returns the `Step` object for a named step. This is used when performing a step, but can also
    # be useful in other contexts.
    # 
    # _@param_ `by_step_name` — the name of the step to find
    sig { params(by_step_name: T.any(Symbol, String)).returns(SORD_ERROR_StepperMotorStep) }
    def self.lookup_step_definition(by_step_name); end

    # Returns all step definitions that follow the given step in the journey
    # 
    # _@param_ `step_definition` — the step to find the following steps for
    # 
    # _@return_ — the following steps, or empty array if this is the last step
    sig { params(step_definition: StepperMotor::Step).returns(T::Array[StepperMotor::Step]) }
    def self.step_definitions_following(step_definition); end

    # sord omit - no YARD type given for "by_step_name", using untyped
    # sord omit - no YARD return type given, using untyped
    # Alias for the class method, for brevity
    # 
    # _@see_ `Journey.lookup_step_definition`
    sig { params(by_step_name: T.untyped).returns(T.untyped) }
    def lookup_step_definition(by_step_name); end

    # Defines a condition that will cause the journey to cancel if satisfied.
    # This works like Rails' `etag` - it's class-inheritable and appendable.
    # Multiple `cancel_if` calls can be made to a Journey definition.
    # All conditions are evaluated after setting the state to `performing`.
    # If any condition is satisfied, the journey will cancel.
    # 
    # _@param_ `condition_arg` — the condition to check
    # 
    # _@param_ `condition_blk` — a block that will be evaluated as a condition
    sig { params(condition_arg: T.any(TrueClass, FalseClass, Symbol, Proc, T::Array[T.untyped], Conditional), condition_blk: T.untyped).void }
    def self.cancel_if(condition_arg = :__no_argument_given__, &condition_blk); end

    # Performs the next step in the journey. Will check whether any other process has performed the step already
    # and whether the record is unchanged, and will then lock it and set the state to 'performimg'.
    # 
    # After setting the state, it will determine the next step to perform, and perform it. Depending on the outcome of
    # the step another `PerformStepJob` may get enqueued. If the journey ends here, the journey record will set its state
    # to 'finished'.
    # 
    # _@param_ `idempotency_key` — If provided, the step will only be performed if the idempotency key matches the current idempotency key. This ensures that the only the triggering job that was scheduled for this step can trigger the step and not any other.
    sig { params(idempotency_key: T.nilable(String)).void }
    def perform_next_step!(idempotency_key: nil); end

    # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
    sig { returns(ActiveSupport::Duration) }
    def time_remaining_until_final_step; end

    # sord omit - no YARD type given for "next_step_definition", using untyped
    # sord omit - no YARD type given for "wait:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(next_step_definition: T.untyped, wait: T.untyped).returns(T.untyped) }
    def set_next_step_and_enqueue(next_step_definition, wait: nil); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def logger; end

    # sord omit - no YARD type given for "step_name", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(step_name: T.untyped).returns(T.untyped) }
    def after_locking_for_step(step_name); end

    # sord omit - no YARD type given for "step_name", using untyped
    # sord omit - no YARD type given for "exception", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(step_name: T.untyped, exception: T.untyped).returns(T.untyped) }
    def after_performing_step_with_exception(step_name, exception); end

    # sord omit - no YARD type given for "step_name", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(step_name: T.untyped).returns(T.untyped) }
    def before_step_starts(step_name); end

    # sord omit - no YARD type given for "step_name", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(step_name: T.untyped).returns(T.untyped) }
    def after_performing_step_without_exception(step_name); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def schedule!; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def recover!; end

    # Is a convenient way to end a hero's journey. Imagine you enter a step where you are inviting a user
    # to rejoin the platform, and are just about to send them an email - but they have already joined. You
    # can therefore cancel their journey. Canceling bails you out of the `step`-defined block and sets the journey record to the `canceled` state.
    # 
    # Calling `cancel!` within a step will abort the execution of the current step.
    # 
    # _@return_ — void
    sig { returns(T.untyped) }
    def cancel!; end

    # sord omit - no YARD type given for "wait:", using untyped
    # Inside a step it is possible to ask StepperMotor to retry to start the step at a later point in time. Maybe now is an inconvenient moment
    # (are you about to send a push notification at 3AM perhaps?). The `wait:` parameter specifies how long to defer reattempting the step for.
    # Reattempting will resume the step from the beginning, so the step should be idempotent.
    # 
    # `reattempt!` may only be called within a step.
    # 
    # _@return_ — void
    sig { params(wait: T.untyped).returns(T.untyped) }
    def reattempt!(wait: nil); end

    # Is used to skip the current step and proceed to the next step in the journey. This is useful when you want to
    # conditionally skip a step based on some business logic without canceling the entire journey. For example,
    # you might want to skip a reminder email step if the user has already taken the required action.
    # 
    # If there are more steps after the current step, `skip!` will schedule the next step to be performed.
    # If the current step is the last step in the journey, `skip!` will finish the journey.
    # 
    # `skip!` may be called within a step or outside of a step for journeys in the `ready` state.
    # When called outside of a step, it will skip the next scheduled step and proceed to the following step.
    # 
    # _@return_ — void
    sig { returns(T.untyped) }
    def skip!; end

    # Is used to pause a Journey at any point. The "paused" state is similar to the "ready" state, except that "perform_next_step!" on the
    # journey will do nothing - even if it is scheduled to be performed. Pausing a Journey can be useful in the following situations:
    # 
    # * The hero of the journey is in a compliance procedure, and their Journeys should not continue
    # * The external resource a Journey will be calling is not available
    # * There is a bug in the Journey implementation and you need some time to get it fixed without canceling or recreating existing Journeys
    # 
    # Calling `pause!` within a step will abort the execution of the current step.
    # 
    # _@return_ — void
    sig { returns(T.untyped) }
    def pause!; end

    # Is used to resume a paused Journey. It places the Journey into the `ready` state and schedules the job to perform that step.
    # 
    # Calling `resume!` is only permitted outside of a step
    # 
    # _@return_ — void
    sig { returns(T.untyped) }
    def resume!; end

    module Recovery
      extend ActiveSupport::Concern

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def recover!; end
    end

    module FlowControl
      # Is a convenient way to end a hero's journey. Imagine you enter a step where you are inviting a user
      # to rejoin the platform, and are just about to send them an email - but they have already joined. You
      # can therefore cancel their journey. Canceling bails you out of the `step`-defined block and sets the journey record to the `canceled` state.
      # 
      # Calling `cancel!` within a step will abort the execution of the current step.
      # 
      # _@return_ — void
      sig { returns(T.untyped) }
      def cancel!; end

      # sord omit - no YARD type given for "wait:", using untyped
      # Inside a step it is possible to ask StepperMotor to retry to start the step at a later point in time. Maybe now is an inconvenient moment
      # (are you about to send a push notification at 3AM perhaps?). The `wait:` parameter specifies how long to defer reattempting the step for.
      # Reattempting will resume the step from the beginning, so the step should be idempotent.
      # 
      # `reattempt!` may only be called within a step.
      # 
      # _@return_ — void
      sig { params(wait: T.untyped).returns(T.untyped) }
      def reattempt!(wait: nil); end

      # Is used to skip the current step and proceed to the next step in the journey. This is useful when you want to
      # conditionally skip a step based on some business logic without canceling the entire journey. For example,
      # you might want to skip a reminder email step if the user has already taken the required action.
      # 
      # If there are more steps after the current step, `skip!` will schedule the next step to be performed.
      # If the current step is the last step in the journey, `skip!` will finish the journey.
      # 
      # `skip!` may be called within a step or outside of a step for journeys in the `ready` state.
      # When called outside of a step, it will skip the next scheduled step and proceed to the following step.
      # 
      # _@return_ — void
      sig { returns(T.untyped) }
      def skip!; end

      # Is used to pause a Journey at any point. The "paused" state is similar to the "ready" state, except that "perform_next_step!" on the
      # journey will do nothing - even if it is scheduled to be performed. Pausing a Journey can be useful in the following situations:
      # 
      # * The hero of the journey is in a compliance procedure, and their Journeys should not continue
      # * The external resource a Journey will be calling is not available
      # * There is a bug in the Journey implementation and you need some time to get it fixed without canceling or recreating existing Journeys
      # 
      # Calling `pause!` within a step will abort the execution of the current step.
      # 
      # _@return_ — void
      sig { returns(T.untyped) }
      def pause!; end

      # Is used to resume a paused Journey. It places the Journey into the `ready` state and schedules the job to perform that step.
      # 
      # Calling `resume!` is only permitted outside of a step
      # 
      # _@return_ — void
      sig { returns(T.untyped) }
      def resume!; end
    end
  end

  class Railtie < Rails::Railtie
  end

  # All StepperMotor job classes inherit from this one. It is available for
  # extension from StepperMotor.extend_base_job_class so that you can set
  # priority, include and prepend modules and so forth.
  class BaseJob < ActiveJob::Base
  end

  # A wrapper for conditional logic that can be evaluated against an object.
  # This class encapsulates different types of conditions (booleans, symbols, callables, arrays)
  # and provides a unified interface for checking if a condition is satisfied by a given object.
  # It handles negation and ensures proper context when evaluating conditions.
  class Conditional
    # sord omit - no YARD type given for "condition", using untyped
    # sord omit - no YARD type given for "negate:", using untyped
    sig { params(condition: T.untyped, negate: T.untyped).void }
    def initialize(condition, negate: false); end

    # sord omit - no YARD type given for "object", using untyped
    sig { params(object: T.untyped).returns(T::Boolean) }
    def satisfied_by?(object); end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def validate_condition; end
  end

  module TestHelper
    # Allows running a given Journey to completion, skipping across the waiting periods.
    # This is useful to evaluate all side effects of a Journey. The helper will ensure
    # that the number of steps performed is equal to the number of steps defined - this way
    # it will not enter into an endless loop. If, after completing all the steps, the journey
    # has neither canceled nor finished, an exception will be raised.
    # 
    # _@param_ `journey` — the journey to speedrun
    # 
    # _@param_ `time_travel` — whether to use ActiveSupport time travel (default: true) Note: When time_travel is true, this method will permanently travel time forward and will not reset it back to the original time when the method exits.
    # 
    # _@param_ `maximum_steps` — how many steps can we take until we assume the journey has hung and fail the test. Default value is :reasonable, which is 10x the number of steps. :unlimited allows "a ton", but can make your test hang if your logic lets a step reattempt indefinitely
    # 
    # _@return_ — void
    sig { params(journey: StepperMotor::Journey, time_travel: T::Boolean, maximum_steps: T.any(Symbol, Integer)).returns(T.untyped) }
    def speedrun_journey(journey, time_travel: true, maximum_steps: :reasonable); end

    # Performs the named step of the journey without waiting for the time to perform the step.
    # 
    # _@param_ `journey` — the journey to speedrun
    # 
    # _@param_ `step_name` — the name of the step to run
    # 
    # _@return_ — void
    sig { params(journey: StepperMotor::Journey, step_name: Symbol).returns(T.untyped) }
    def immediately_perform_single_step(journey, step_name); end
  end

  # The generator is used to install StepperMotor. It adds an example Journey, a configing
  # initializer and the migration that creates tables.
  # Run it with `bin/rails g stepper_motor:install` in your console.
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration
    UUID_MESSAGE = T.let(<<~MSG, T.untyped)
  If set, uuid type will be used for hero_id of the Journeys, as well as for the Journey IDs.
  Use this if most of your models use UUD as primary key"
MSG

    # sord omit - no YARD return type given, using untyped
    # Generates monolithic migration file that contains all database changes.
    sig { returns(T.untyped) }
    def create_migration_file; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def create_initializer; end

    sig { returns(T::Boolean) }
    def uuid_fk?; end

    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def migration_version; end
  end

  # The cyclic scheduler is designed to be run regularly via a cron job. On every
  # cycle, it is going to look for Journeys which are going to come up for step execution
  # before the next cycle is supposed to run. Then it is going to enqueue jobs to perform
  # steps on those journeys. Since the scheduler gets run at a discrete interval, but we
  # still them to be processed on time, if we only picked up the journeys which have the
  # step execution time set to now or earlier, we will always have delays. This is why
  # this scheduler enqueues jobs for journeys whose time to run is between now and the
  # next cycle.
  # 
  # Once the job gets created, it then gets enqueued and gets picked up by the ActiveJob
  # worker normally. If you are using SQS, which has a limit of 900 seconds for the `wait:`
  # value, you need to run the scheduler at least (!) every 900 seconds, and preferably
  # more frequently (for example, once every 5 minutes). This scheduler is also going to be
  # more gentle with ActiveJob adapters that may get slower with large queue depths, such as
  # good_job. This scheduler is a good fit if you are using an ActiveJob adapter which:
  # 
  # * Does not allow easy introspection of jobs in the future (like Redis-based queues)
  # * Limits the value of the `wait:` parameter
  # 
  # The scheduler needs to be configured in your cron table.
  class CyclicScheduler < StepperMotor::ForwardScheduler
    # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
    # Creates a new scheduler. The scheduler needs to know how frequently it is going to be running -
    # you define that frequency when you configure your cron job that calls `run_scheduling_cycle`. Journeys which
    # have to perform their steps between the runs of the cycles will generate jobs. The more frequent the scheduling
    # cycle, the fewer jobs are going to be created per cycle.
    # 
    # _@param_ `cycle_duration` — how frequently the scheduler runs
    sig { params(cycle_duration: ActiveSupport::Duration).void }
    def initialize(cycle_duration:); end

    # Run a scheduling cycle. This should be called from your ActiveJob that runs on a regular Cron cadence. Ideally you
    # would call the instance of the scheduler configured for the whole StepperMotor (so that the `cycle_duration` gets
    # correctly applied, as it is necessary to pick the journeys to step). Normally, you would do this:
    sig { void }
    def run_scheduling_cycle; end

    # sord omit - no YARD type given for "journey", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(journey: T.untyped).returns(T.untyped) }
    def schedule(journey); end

    class RunSchedulingCycleJob < StepperMotor::BaseJob
      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def perform; end
    end
  end

  class HousekeepingJob < StepperMotor::BaseJob
    # sord omit - no YARD return type given, using untyped
    sig { returns(T.untyped) }
    def perform; end
  end

  class PerformStepJob < StepperMotor::BaseJob
    # sord omit - no YARD type given for "*posargs", using untyped
    # sord omit - no YARD type given for "**kwargs", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(posargs: T.untyped, kwargs: T.untyped).returns(T.untyped) }
    def perform(*posargs, **kwargs); end

    # sord omit - no YARD type given for "journey_gid", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(journey_gid: T.untyped).returns(T.untyped) }
    def perform_via_journey_gid(journey_gid); end

    # sord omit - no YARD type given for "journey_id:", using untyped
    # sord omit - no YARD type given for "journey_class_name:", using untyped
    # sord omit - no YARD type given for "idempotency_key:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(journey_id: T.untyped, journey_class_name: T.untyped, idempotency_key: T.untyped).returns(T.untyped) }
    def perform_via_kwargs(journey_id:, journey_class_name:, idempotency_key: nil); end
  end

  # The forward scheduler enqueues a job for every Journey that
  # gets sent to the `#schedule`. The job is then stored in the queue
  # and gets picked up by the ActiveJob worker normally. This is the simplest
  # option if your ActiveJob adapter supports far-ahead scheduling. Some adapters,
  # such as SQS, have limitations regarding the maximum delay after which a message
  # will become visible. For SQS, the limit is 900 seconds. If the job is further in the future,
  # it is likely going to fail to get enqueued. If you are working with a queue adapter that:
  # 
  # * Does not allow easy introspection of jobs in the future (like Redis-based queues)
  # * Limits the value of the `wait:` parameter
  # 
  # this scheduler may not be a good fit for you, and you will need to use the {CyclicScheduler} instead.
  # Note that this scheduler is also likely to populate your queue with a high number of "far out"
  # jobs to be performed in the future. Different ActiveJob adapters are known to have varying
  # performance depending on the number of jobs in the queue. For example, good_job is known to
  # struggle a bit if the queue contains a large number of jobs (even if those jobs are not yet
  # scheduled to be performed). For good_job the {CyclicScheduler} is also likely to be a better option.
  class ForwardScheduler
    # sord omit - no YARD type given for "journey", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(journey: T.untyped).returns(T.untyped) }
    def schedule(journey); end
  end

  # The purpose of this job is to find journeys which have, for whatever reason, remained in the
  # `performing` state for far longer than the journey is supposed to. At the moment it assumes
  # any journey that stayed in `performing` for longer than 1 hour has hung. Add this job to your
  # cron table and perform it regularly.
  class RecoverStuckJourneysJob < StepperMotor::BaseJob
    DEFAULT_STUCK_FOR = T.let(2.days, T.untyped)

    # sord omit - no YARD type given for "stuck_for:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(stuck_for: T.untyped).returns(T.untyped) }
    def perform(stuck_for: DEFAULT_STUCK_FOR); end
  end

  # The purpose of this job is to find journeys which have completed (finished or canceled) some
  # time ago and to delete them. The time is configured in the initializer.
  class DeleteCompletedJourneysJob < StepperMotor::BaseJob
    # sord omit - no YARD type given for "completed_for:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(completed_for: T.untyped).returns(T.untyped) }
    def perform(completed_for: StepperMotor.delete_completed_journeys_after); end
  end
end
