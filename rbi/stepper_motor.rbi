# typed: strong
# StepperMotor is a module for building multi-step flows where steps are sequential and only
# ever progress forward. The building block of StepperMotor is StepperMotor::Journey
module StepperMotor
  VERSION = T.let("0.1.7", T.untyped)

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
    # sord omit - no YARD type given for "seq:", using untyped
    # sord warn - ActiveSupport::Duration wasn't able to be resolved to a constant in this project
    # Creates a new step definition
    # 
    # _@param_ `name` — the name of the Step
    # 
    # _@param_ `wait` — the amount of time to wait before entering the step
    # 
    # _@param_ `on_exception` — the action to take if an exception occurs when performing the step. The possible values are: * `:cancel!` - cancels the Journey and re-raises the exception. The Journey will be persisted before re-raising. * `:reattempt!` - reattempts the Journey and re-raises the exception. The Journey will be persisted before re-raising.
    sig do
      params(
        name: T.any(String, Symbol),
        seq: T.untyped,
        on_exception: Symbol,
        wait: T.any(Numeric, ActiveSupport::Duration),
        step_block: T.untyped
      ).void
    end
    def initialize(name:, seq:, on_exception:, wait: 0, &step_block); end

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

    # sord omit - no YARD type given for :seq, using untyped
    sig { returns(T.untyped) }
    attr_reader :seq

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
    include StepperMotor::Journey::Recovery
    STATES = T.let(%w[ready performing canceled finished], T.untyped)

    # sord omit - no YARD return type given, using untyped
    # Alias for the class attribute, for brevity
    # 
    # _@see_ `Journey.step_definitions`
    sig { returns(T.untyped) }
    def step_definitions; end

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
    # _@param_ `after` — the amount of time this step should wait before getting performed including all the previous waits. This allows you to set the wait time based on the time after the journey started, as opposed to when the previous step has completed. When the journey gets scheduled, the triggering job is going to be delayed by this amount of time _minus the `wait` values of the preceding steps, and the `next_step_to_be_performed_at` attribute will be set to the current time. The `after` value gets converted into the `wait` value and passed to the step definition. Mutually exclusive with `wait:`
    # 
    # _@param_ `on_exception` — See {StepperMotor::Step#on_exception}
    # 
    # _@param_ `additional_step_definition_options` — Any remaining options get passed to `StepperMotor::Step.new` as keyword arguments.
    # 
    # _@return_ — the step definition that has been created
    sig do
      params(
        name: T.nilable(String),
        wait: T.nilable(T.any(Float, T.untyped, ActiveSupport::Duration)),
        after: T.nilable(T.any(Float, T.untyped, ActiveSupport::Duration)),
        on_exception: Symbol,
        additional_step_definition_options: T.untyped,
        blk: T.untyped
      ).returns(StepperMotor::Step)
    end
    def self.step(name = nil, wait: nil, after: nil, on_exception: :cancel!, **additional_step_definition_options, &blk); end

    # sord warn - "StepperMotor::Step?" does not appear to be a type
    # Returns the `Step` object for a named step. This is used when performing a step, but can also
    # be useful in other contexts.
    # 
    # _@param_ `by_step_name` — the name of the step to find
    sig { params(by_step_name: T.any(Symbol, String)).returns(SORD_ERROR_StepperMotorStep) }
    def self.lookup_step_definition(by_step_name); end

    # sord omit - no YARD type given for "by_step_name", using untyped
    # sord omit - no YARD return type given, using untyped
    # Alias for the class method, for brevity
    # 
    # _@see_ `Journey.lookup_step_definition`
    sig { params(by_step_name: T.untyped).returns(T.untyped) }
    def lookup_step_definition(by_step_name); end

    # sord omit - no YARD return type given, using untyped
    # Is a convenient way to end a hero's journey. Imagine you enter a step where you are inviting a user
    # to rejoin the platform, and are just about to send them an email - but they have already joined. You
    # can therefore cancel their journey. Canceling bails you out of the `step`-defined block and sets the journey record to the `canceled` state.
    # 
    # Calling `cancel!` will abort the execution of the current step.
    sig { returns(T.untyped) }
    def cancel!; end

    # sord omit - no YARD type given for "wait:", using untyped
    # sord omit - no YARD return type given, using untyped
    # Inside a step it is possible to ask StepperMotor to retry to start the step at a later point in time. Maybe now is an inconvenient moment
    # (are you about to send a push notification at 3AM perhaps?). The `wait:` parameter specifies how long to defer reattempting the step for.
    # Reattempting will resume the step from the beginning, so the step should be idempotent.
    # 
    # Calling `reattempt!` will abort the execution of the current step.
    sig { params(wait: T.untyped).returns(T.untyped) }
    def reattempt!(wait: nil); end

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

    module Recovery
      extend ActiveSupport::Concern

      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def recover!; end
    end
  end

  class Railtie < Rails::Railtie
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
    # _@return_ — void
    sig { params(journey: StepperMotor::Journey).returns(T.untyped) }
    def speedrun_journey(journey); end

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
  If set, uuid type will be used for hero_id. Use this
  if most of your models use UUD as primary key"
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

    class RunSchedulingCycleJob < ActiveJob::Base
      # sord omit - no YARD return type given, using untyped
      sig { returns(T.untyped) }
      def perform; end
    end
  end

  class PerformStepJob < ActiveJob::Base
    # sord omit - no YARD type given for "journey_gid", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(journey_gid: T.untyped).returns(T.untyped) }
    def perform(journey_gid); end
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

  class PerformStepJobV2 < ActiveJob::Base
    # sord omit - no YARD type given for "journey_id:", using untyped
    # sord omit - no YARD type given for "journey_class_name:", using untyped
    # sord omit - no YARD type given for "idempotency_key:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(journey_id: T.untyped, journey_class_name: T.untyped, idempotency_key: T.untyped).returns(T.untyped) }
    def perform(journey_id:, journey_class_name:, idempotency_key: nil); end
  end

  # The purpose of this job is to find journeys which have, for whatever reason, remained in the
  # `performing` state for far longer than the journey is supposed to. At the moment it assumes
  # any journey that stayed in `performing` for longer than 1 hour has hung. Add this job to your
  # cron table and perform it regularly.
  class RecoverStuckJourneysJobV1 < ActiveJob::Base
    DEFAULT_STUCK_FOR = T.let(2.days, T.untyped)

    # sord omit - no YARD type given for "stuck_for:", using untyped
    # sord omit - no YARD return type given, using untyped
    sig { params(stuck_for: T.untyped).returns(T.untyped) }
    def perform(stuck_for: DEFAULT_STUCK_FOR); end
  end
end
