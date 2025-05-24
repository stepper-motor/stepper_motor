# frozen_string_literal: true

# StepperMotor is a module for building multi-step flows where steps are sequential and only
# ever progress forward. The building block of StepperMotor is StepperMotor::Journey
module StepperMotor
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
  #       step, wait: 3.days do
  #         cancel! if hero.active?
  #         ReinviteMailer.with(recipient: hero).deliver_later
  #       end
  #
  #       step, wait: 3.days do
  #         cancel! if hero.active?
  #         ReinviteMailer.with(recipient: hero).deliver_later
  #       end
  #
  #       step, wait: 3.days do
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
    require_relative "journey/recovery"
    include StepperMotor::Journey::Recovery

    self.table_name = "stepper_motor_journeys"

    # @return [Array] the step definitions defined so far
    class_attribute :step_definitions, default: []

    belongs_to :hero, polymorphic: true, optional: true

    STATES = %w[ready performing canceled finished]
    enum :state, STATES.zip(STATES).to_h, default: "ready"

    # Allows querying for journeys for this specific hero. This uses a scope for convenience as the hero
    # is referenced using it's global ID (same ID that ActiveJob uses for serialization)
    scope :for_hero, ->(hero) {
      where(hero: hero)
    }

    after_create do |journey|
      journey.step_definitions.any? ? journey.set_next_step_and_enqueue(journey.step_definitions.first) : journey.finished!
    end

    # Defines a step in the journey.
    # Steps are stacked top to bottom and get performed in sequence.
    #
    # @param name[String?] the name of the step. If none is provided, a name will be automatically generated based
    #    on the position of the step in the list of `step_definitions`. The name can also be used to call a method
    #    on the `Journey` instead of calling the provided block.
    # @param wait[Float, #to_f, ActiveSupport::Duration] the amount of time this step should wait before getting performed.
    #    When the journey gets scheduled, the triggering job is going to be delayed by this amount of time, and the
    #    `next_step_to_be_performed_at` attribute will be set to the current time plus the wait duration. Mutually exclusive with `after:`
    # @param after[Float, #to_f, ActiveSupport::Duration] the amount of time this step should wait before getting performed
    #    including all the previous waits. This allows you to set the wait time based on the time after the journey started, as opposed
    #    to when the previous step has completed. When the journey gets scheduled, the triggering job is going to be delayed by this
    #    amount of time _minus the `wait` values of the preceding steps, and the
    #    `next_step_to_be_performed_at` attribute will be set to the current time. The `after` value gets converted into the `wait`
    #    value and passed to the step definition. Mutually exclusive with `wait:`
    # @param step_definition_options Any remaining options get passed to `StepperMotor::Step.new` as keyword arguments.
    # @return [StepperMotor::Step] the step definition that has been created
    def self.step(name = nil, wait: nil, after: nil, **step_definition_options, &blk)
      wait = if wait && after
        raise StepConfigurationError, "Either wait: or after: can be specified, but not both"
      elsif !wait && !after
        0
      elsif after
        accumulated = step_definitions.map(&:wait).sum
        after - accumulated
      else
        wait
      end
      raise StepConfigurationError, "wait: cannot be negative, but computed was #{wait}s" if wait.negative?
      name ||= "step_%d" % (step_definitions.length + 1)
      name = name.to_s

      known_step_names = step_definitions.map(&:name)
      raise StepConfigurationError, "Step named #{name.inspect} already defined" if known_step_names.include?(name)

      # Create the step definition
      StepperMotor::Step.new(name: name, wait: wait, seq: step_definitions.length, &blk).tap do |step_definition|
        # As per Rails docs: you need to be aware when using class_attribute with mutable structures
        # as Array or Hash. In such cases, you don't want to do changes in place. Instead use setters.
        # See https://apidock.com/rails/v7.1.3.2/Class/class_attribute
        self.step_definitions = step_definitions + [step_definition]
      end
    end

    # Returns the `Step` object for a named step. This is used when performing a step, but can also
    # be useful in other contexts.
    #
    # @param by_step_name[Symbol,String] the name of the step to find
    # @return [StepperMotor::Step?]
    def self.lookup_step_definition(by_step_name)
      step_definitions.find { |d| d.name.to_s == by_step_name.to_s }
    end

    # Alias for the class attribute, for brevity
    #
    # @see Journey.step_definitions
    def step_definitions
      self.class.step_definitions
    end

    # Alias for the class method, for brevity
    #
    # @see Journey.lookup_step_definition
    def lookup_step_definition(by_step_name)
      self.class.lookup_step_definition(by_step_name)
    end

    # Is a convenient way to end a hero's journey. Imagine you enter a step where you are inviting a user
    # to rejoin the platform, and are just about to send them an email - but they have already joined. You
    # can therefore cancel their journey. Canceling bails you out of the `step`-defined block and sets the journey record to the `canceled` state.
    #
    # Calling `cancel!` will abort the execution of the current step.
    def cancel!
      canceled!
      throw :abort_step
    end

    # Inside a step it is possible to ask StepperMotor to retry to start the step at a later point in time. Maybe now is an inconvenient moment
    # (are you about to send a push notification at 3AM perhaps?). The `wait:` parameter specifies how long to defer reattempting the step for.
    # Reattempting will resume the step from the beginning, so the step should be idempotent.
    #
    # Calling `reattempt!` will abort the execution of the current step.
    def reattempt!(wait: nil)
      # The default `wait` is the one for the step definition
      @reattempt_after = wait || @current_step_definition.wait || 0
      throw :abort_step
    end

    # Performs the next step in the journey. Will check whether any other process has performed the step already
    # and whether the record is unchanged, and will then lock it and set the state to 'performimg'.
    #
    # After setting the state, it will determine the next step to perform, and perform it. Depending on the outcome of
    # the step another `PerformStepJob` may get enqueued. If the journey ends here, the journey record will set its state
    # to 'finished'.
    #
    # @param idempotency_key [String, nil] If provided, the step will only be performed if the idempotency key matches the current idempotency key.
    #   This ensures that the only the triggering job that was scheduled for this step can trigger the step and not any other.
    # @return [void]
    def perform_next_step!(idempotency_key: nil)
      # Make sure we can't start running the same step of the same journey twice
      next_step_name_before_locking = next_step_name
      with_lock do
        # Make sure no other worker has snatched this journey and made steps instead of us
        return unless ready? && next_step_name == next_step_name_before_locking
        # Check idempotency key if both are present
        return if idempotency_key && idempotency_key != self.idempotency_key

        performing!
        after_locking_for_step(next_step_name)
      end
      current_step_name = next_step_name

      if current_step_name
        logger.debug { "preparing to perform step #{current_step_name}" }
      else
        logger.debug { "no next step - finishing journey" }
        # If there is no step set - just terminate the journey
        return finished! unless current_step_name
      end

      before_step_starts(current_step_name)

      # Recover the step definition
      @current_step_definition = lookup_step_definition(current_step_name)

      unless @current_step_definition
        logger.debug { "no definition for #{current_step_name} - finishing journey" }
        return finished!
      end

      # Is we tried to run the step but it is not yet time to do so,
      # enqueue a new job to perform it and stop
      if next_step_to_be_performed_at > Time.current
        logger.warn { "tried to perform #{current_step_name} prematurely" }
        schedule!
        return ready!
      end

      # Perform the actual step
      increment!(:steps_entered)
      logger.debug { "entering step #{current_step_name}" }

      catch(:abort_step) do
        @current_step_definition.perform_in_context_of(self)
      end

      # By the end of the step the Journey must either be untouched or saved
      if changed?
        raise StepperMotor::JourneyNotPersisted, <<~MSG
          #{self} had its attributes changed but was not saved inside step #{current_step_name.inspect}
          this means that the subsequent execution (which may be done asynchronously) is likely to see
          a stale Journey, and will execute incorrectly. If you mutate the Journey inside
          of a step, make sure to call `save!` or use methods that save in-place
          (such as `increment!`).
        MSG
      end

      increment!(:steps_completed)
      logger.debug { "completed #{current_step_name} without exceptions" }

      if canceled?
        # The step aborted the journey, nothing to do
        logger.info { "has been canceled inside #{current_step_name}" }
      elsif @reattempt_after
        # The step asked the actions to be attempted at a later time
        logger.info { "will reattempt #{current_step_name} in #{@reattempt_after} seconds" }
        set_next_step_and_enqueue(@current_step_definition, wait: @reattempt_after)
        ready!
      elsif finished?
        logger.info { "was marked finished inside the step" }
        update!(previous_step_name: current_step_name, next_step_name: nil)
      elsif (next_step_definition = step_definitions[@current_step_definition.seq + 1])
        logger.info { "will continue to #{next_step_definition.name}" }
        set_next_step_and_enqueue(next_step_definition)
        ready!
      else
        # The hero's journey is complete
        logger.info { "journey completed" }
        finished!
        update!(previous_step_name: current_step_name, next_step_name: nil)
      end
    ensure
      # The instance variables must not be present if `perform_next_step!` gets called
      # on this same object again. This will be the case if the steps are performed inline
      # and not via background jobs (which reload the model)
      @reattempt_after = nil
      @current_step_definition = nil
      after_step_completes(current_step_name) if current_step_name
    end

    # @return [ActiveSupport::Duration]
    def time_remaining_until_final_step
      current_step_seq = @current_step_definition&.seq || -1
      subsequent_steps = step_definitions.select { |definition| definition.seq > current_step_seq }
      seconds_remaining = subsequent_steps.map { |definition| definition.wait.to_f }.sum
      seconds_remaining.seconds # Convert to ActiveSupport::Duration
    end

    def set_next_step_and_enqueue(next_step_definition, wait: nil)
      wait ||= next_step_definition.wait
      next_idempotency_key = SecureRandom.base36(16)
      update!(previous_step_name: next_step_name, next_step_name: next_step_definition.name, next_step_to_be_performed_at: Time.current + wait, idempotency_key: next_idempotency_key)
      schedule!
    end

    def logger
      if (logger_from_parent = super)
        tag = [self.class.to_s, to_param].join(":")
        tag << " at " << @current_step_definition.name if @current_step_definition
        logger_from_parent.tagged(tag)
      else
        # Furnish a "null logger"
        ActiveSupport::Logger.new(nil)
      end
    end

    def after_locking_for_step(step_name)
    end

    def before_step_starts(step_name)
    end

    def after_step_completes(step_name)
    end

    def schedule!
      StepperMotor.scheduler.schedule(self)
    end
  end
end
