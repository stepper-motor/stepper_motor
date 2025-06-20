# frozen_string_literal: true

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
    require_relative "journey/flow_control"
    include StepperMotor::Journey::FlowControl

    require_relative "journey/recovery"
    include StepperMotor::Journey::Recovery

    self.table_name = "stepper_motor_journeys"

    # @return [Array<StepperMotor::Step>] the step definitions defined so far
    class_attribute :step_definitions, default: []

    # @return [Array<StepperMotor::Conditional>] the cancel_if conditions defined for this journey class
    class_attribute :cancel_if_conditions, default: []

    # @return [Array<StepperMotor::Conditional>] the skip_if conditions defined for this journey class
    class_attribute :skip_if_conditions, default: []

    belongs_to :hero, polymorphic: true, optional: true

    STATES = %w[ready paused performing canceled finished]
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
    # @param name[String,nil] the name of the step. If none is provided, a name will be automatically generated based
    #    on the position of the step in the list of `step_definitions`. The name can also be used to call a method
    #    on the `Journey` instead of calling the provided block.
    # @param wait[Float,#to_f,ActiveSupport::Duration] the amount of time this step should wait before getting performed.
    #    When the journey gets scheduled, the triggering job is going to be delayed by this amount of time, and the
    #    `next_step_to_be_performed_at` attribute will be set to the current time plus the wait duration. Mutually exclusive with `after:`
    # @param after[Float,#to_f,ActiveSupport::Duration] the amount of time this step should wait before getting performed
    #    including all the previous waits. This allows you to set the wait time based on the time after the journey started,
    #    as opposed to when the previous step has completed. When the journey gets scheduled, the triggering job is going to
    #    be delayed by this amount of time _minus the `wait` values of the preceding steps, and the `next_step_to_be_performed_at`
    #    attribute will be set to the current time. The `after` value gets converted into the `wait` value and passed to the step definition.
    #    Mutually exclusive with `wait:`
    # @param on_exception[Symbol] See {StepperMotor::Step#on_exception}
    # @param skip_if[TrueClass,FalseClass,Symbol,Proc] condition to check before performing the step. If a symbol is provided,
    #    it will call the method on the Journey. If a block is provided, it will be executed with the Journey as context.
    #    The step will be skipped if the condition returns a truthy value.
    # @param if[TrueClass,FalseClass,Symbol,Proc] condition to check before performing the step. If a symbol is provided,
    #    it will call the method on the Journey. If a block is provided, it will be executed with the Journey as context.
    #    The step will be performed if the condition returns a truthy value. and skipped otherwise. Inverse of `skip_if`.
    # @param additional_step_definition_options[Hash] Any remaining options get passed to `StepperMotor::Step.new` as keyword arguments.
    # @return [StepperMotor::Step] the step definition that has been created
    def self.step(name = nil, wait: nil, after: nil, **additional_step_definition_options, &blk)
      # Handle the if: alias for backward compatibility
      if additional_step_definition_options.key?(:if) && additional_step_definition_options.key?(:skip_if)
        raise StepConfigurationError, "Either skip_if: or if: can be specified, but not both"
      end
      if additional_step_definition_options.key?(:if)
        # Convert if: to skip_if:
        additional_step_definition_options[:skip_if] = StepperMotor::Conditional.new(additional_step_definition_options.delete(:if), negate: true)
      end

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

      if name.blank? && blk.blank?
        raise StepConfigurationError, <<~MSG
          Step #{step_definitions.length + 1} of #{self} has no explicit name,
          and no block with step definition has been provided. Without a name the step
          must be defined with a block to execute. If you want an instance method of
          this Journey to be used as the step, pass the name of the method as the name of the step.
        MSG
      end

      name ||= "step_%d" % (step_definitions.length + 1)
      name = name.to_s

      known_step_names = step_definitions.map(&:name)
      raise StepConfigurationError, "Step named #{name.inspect} already defined" if known_step_names.include?(name)

      # Create the step definition
      StepperMotor::Step.new(name: name, wait: wait, seq: step_definitions.length, **additional_step_definition_options, &blk).tap do |step_definition|
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

    # Alias for the class attribute, for brevity
    #
    # @see Journey.cancel_if_conditions
    def cancel_if_conditions
      self.class.cancel_if_conditions
    end

    # Alias for the class attribute, for brevity
    #
    # @see Journey.skip_if_conditions
    def skip_if_conditions
      self.class.skip_if_conditions
    end

    # Defines a condition that will cause the journey to cancel if satisfied.
    # This works like Rails' `etag` - it's class-inheritable and appendable.
    # Multiple `cancel_if` calls can be made to a Journey definition.
    # All conditions are evaluated after setting the state to `performing`.
    # If any condition is satisfied, the journey will cancel.
    #
    # @param condition_arg [TrueClass, FalseClass, Symbol, Proc, Array, Conditional] the condition to check
    # @param condition_blk [Proc] a block that will be evaluated as a condition
    # @return [void]
    def self.cancel_if(condition_arg = :__no_argument_given__, &condition_blk)
      # Check if neither argument nor block is provided
      if condition_arg == :__no_argument_given__ && !condition_blk
        raise ArgumentError, "cancel_if requires either a condition argument or a block"
      end

      # Check if both argument and block are provided
      if condition_arg != :__no_argument_given__ && condition_blk
        raise ArgumentError, "cancel_if accepts either a condition argument or a block, but not both"
      end

      # Select the condition: positional argument takes precedence if not sentinel
      condition = if condition_arg != :__no_argument_given__
        condition_arg
      else
        condition_blk
      end

      conditional = StepperMotor::Conditional.new(condition)

      # As per Rails docs: you need to be aware when using class_attribute with mutable structures
      # as Array or Hash. In such cases, you don't want to do changes in place. Instead use setters.
      # See https://apidock.com/rails/v7.1.3.2/Class/class_attribute
      self.cancel_if_conditions = cancel_if_conditions + [conditional]
    end

    # Defines a condition that will cause the current step to be skipped if satisfied.
    # This works like Rails' `etag` - it's class-inheritable and appendable.
    # Multiple `skip_if` calls can be made to a Journey definition.
    # All conditions are evaluated after setting the state to `performing` but before step execution.
    # If any condition is satisfied, the current step will be skipped and the journey will proceed to the next step.
    #
    # @param condition_arg [TrueClass, FalseClass, Symbol, Proc, Array, Conditional] the condition to check
    # @param condition_blk [Proc] a block that will be evaluated as a condition
    # @return [void]
    def self.skip_if(condition_arg = :__no_argument_given__, &condition_blk)
      # Check if neither argument nor block is provided
      if condition_arg == :__no_argument_given__ && !condition_blk
        raise ArgumentError, "skip_if requires either a condition argument or a block"
      end

      # Check if both argument and block are provided
      if condition_arg != :__no_argument_given__ && condition_blk
        raise ArgumentError, "skip_if accepts either a condition argument or a block, but not both"
      end

      # Select the condition: positional argument takes precedence if not sentinel
      condition = if condition_arg != :__no_argument_given__
        condition_arg
      else
        condition_blk
      end

      conditional = StepperMotor::Conditional.new(condition)

      # As per Rails docs: you need to be aware when using class_attribute with mutable structures
      # as Array or Hash. In such cases, you don't want to do changes in place. Instead use setters.
      # See https://apidock.com/rails/v7.1.3.2/Class/class_attribute
      self.skip_if_conditions = skip_if_conditions + [conditional]
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

      # Check cancel_if conditions after setting state to performing
      if cancel_if_conditions.any? { |conditional| conditional.satisfied_by?(self) }
        logger.info { "cancel_if condition satisfied, canceling journey" }
        cancel!
        return
      end

      # Check skip_if conditions after setting state to performing
      if skip_if_conditions.any? { |conditional| conditional.satisfied_by?(self) }
        logger.info { "skip_if condition satisfied, skipping current step" }
        current_step_name = next_step_name
        current_step_definition = lookup_step_definition(current_step_name)
        
        if current_step_definition
          current_step_seq = current_step_definition.seq
          next_step_definition = step_definitions[current_step_seq + 1]

          if next_step_definition
            # There are more steps after this one - schedule the next step
            logger.info { "skipping current step #{current_step_name}, will continue to #{next_step_definition.name}" }
            set_next_step_and_enqueue(next_step_definition)
            ready!
          else
            # This is the last step - finish the journey
            logger.info { "skipping current step #{current_step_name}, finishing journey" }
            finished!
            update!(previous_step_name: current_step_name, next_step_name: nil)
          end
        else
          # No step definition found - finish the journey
          logger.warn { "no step definition found for #{current_step_name} - finishing journey" }
          finished!
        end
        return
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

      # The flow control for reattempt! and cancel! happens inside perform_in_context_of
      ex_rescued_at_perform = nil
      begin
        @current_step_definition.perform_in_context_of(self)
      rescue => e
        ex_rescued_at_perform = e
        logger.debug { "#{e} raised during #{@current_step_definition.name}, will be re-raised after" }
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

      if ex_rescued_at_perform
        logger.warn { "performed #{current_step_name}, #{ex_rescued_at_perform} was raised" }
      else
        increment!(:steps_completed)
        logger.debug { "performed #{current_step_name} without exceptions" }
      end

      if paused? || canceled?
        # The step made arrangements regarding how we shoudl continue, nothing to do
        logger.info { "has been #{state} inside #{current_step_name}" }
      elsif @reattempt_after
        # The step asked the actions to be attempted at a later time
        logger.info { "will reattempt #{current_step_name} in #{@reattempt_after} seconds" }
        set_next_step_and_enqueue(@current_step_definition, wait: @reattempt_after)
        ready!
      elsif @skip_current_step
        # The step asked to be skipped
        current_step_seq = @current_step_definition.seq
        next_step_definition = step_definitions[current_step_seq + 1]

        if next_step_definition
          # There are more steps after this one - schedule the next step
          logger.info { "skipping current step #{current_step_name}, will continue to #{next_step_definition.name}" }
          set_next_step_and_enqueue(next_step_definition)
          ready!
        else
          # This is the last step - finish the journey
          logger.info { "skipping current step #{current_step_name}, finishing journey" }
          finished!
          update!(previous_step_name: current_step_name, next_step_name: nil)
        end
      elsif finished?
        logger.info { "was marked finished inside the step" }
        update!(previous_step_name: current_step_name, next_step_name: nil)
      elsif (next_step_definition = step_definitions[@current_step_definition.seq + 1])
        logger.info { "will continue to #{next_step_definition.name}" }
        set_next_step_and_enqueue(next_step_definition)
        ready!
      else
        logger.info { "has finished" } # The hero's journey is complete
        finished!
        update!(previous_step_name: current_step_name, next_step_name: nil)
      end
    ensure
      # The instance variables must not be present if `perform_next_step!` gets called
      # on this same object again. This will be the case if the steps are performed inline
      # and not via background jobs (which reload the model). This should actually be solved
      # using some object that contains the state of the action later, but for now - the dirty approach is fine.
      @reattempt_after = nil
      @skip_current_step = nil
      @current_step_definition = nil
      # Re-raise the exception, now that we have persisted the Journey according to the recovery policy
      if ex_rescued_at_perform
        after_performing_step_with_exception(current_step_name, ex_rescued_at_perform) if current_step_name
        raise ex_rescued_at_perform
      elsif current_step_name
        after_performing_step_without_exception(current_step_name)
      end
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

    def after_performing_step_with_exception(step_name, exception)
    end

    def before_step_starts(step_name)
    end

    def after_performing_step_without_exception(step_name)
    end

    def schedule!
      StepperMotor.scheduler.schedule(self)
    end
  end
end
