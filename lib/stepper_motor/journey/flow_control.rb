# frozen_string_literal: true

module StepperMotor::Journey::FlowControl
  # Is a convenient way to end a hero's journey. Imagine you enter a step where you are inviting a user
  # to rejoin the platform, and are just about to send them an email - but they have already joined. You
  # can therefore cancel their journey. Canceling bails you out of the `step`-defined block and sets the journey record to the `canceled` state.
  #
  # Calling `cancel!` within a step will abort the execution of the current step.
  #
  # @return void
  def cancel!
    canceled!
    throw :abort_step if @current_step_definition
  end

  # Inside a step it is possible to ask StepperMotor to retry to start the step at a later point in time. Maybe now is an inconvenient moment
  # (are you about to send a push notification at 3AM perhaps?). The `wait:` parameter specifies how long to defer reattempting the step for.
  # Reattempting will resume the step from the beginning, so the step should be idempotent.
  #
  # `reattempt!` may only be called within a step.
  #
  # @return void
  def reattempt!(wait: nil)
    raise "reattempt! can only be called within a step" unless @current_step_definition
    # The default `wait` is the one for the step definition
    @reattempt_after = wait || @current_step_definition.wait || 0
    throw :abort_step if @current_step_definition
  end

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
  # @return void
  def skip!
    if @current_step_definition
      # Called within a step - set flag to skip current step
      @skip_current_step = true
      throw :abort_step if @current_step_definition
    else
      # Called outside of a step - skip next scheduled step
      with_lock do
        raise "skip! can only be used on journeys in the `ready` state, but was in #{state.inspect}" unless ready?

        current_step_name = next_step_name
        current_step_definition = lookup_step_definition(current_step_name)

        unless current_step_definition
          logger.warn { "no step definition found for #{current_step_name} - finishing journey" }
          finished!
          update!(previous_step_name: current_step_name, next_step_name: nil)
          return
        end

        current_step_seq = current_step_definition.seq
        next_step_definition = step_definitions[current_step_seq + 1]

        if next_step_definition
          # There are more steps after this one - schedule the next step
          logger.info { "skipping scheduled step #{current_step_name}, will continue to #{next_step_definition.name}" }
          set_next_step_and_enqueue(next_step_definition)
          ready!
        else
          # This is the last step - finish the journey
          logger.info { "skipping scheduled step #{current_step_name}, finishing journey" }
          finished!
          update!(previous_step_name: current_step_name, next_step_name: nil)
        end
      end
    end
  end

  # Is used to pause a Journey at any point. The "paused" state is similar to the "ready" state, except that "perform_next_step!" on the
  # journey will do nothing - even if it is scheduled to be performed. Pausing a Journey can be useful in the following situations:
  #
  # * The hero of the journey is in a compliance procedure, and their Journeys should not continue
  # * The external resource a Journey will be calling is not available
  # * There is a bug in the Journey implementation and you need some time to get it fixed without canceling or recreating existing Journeys
  #
  # Calling `pause!` within a step will abort the execution of the current step.
  #
  # @return void
  def pause!
    paused!
    throw :abort_step if @current_step_definition
  end

  # Is used to resume a paused Journey. It places the Journey into the `ready` state and schedules the job to perform that step.
  #
  # Calling `resume!` is only permitted outside of a step
  #
  # @return void
  def resume!
    raise "resume! can only be used outside of a step" if @current_step_definition
    with_lock do
      raise "The #{self.class} to resume must be in the `paused' state, but was in #{state.inspect}" unless paused?
      update!(state: "ready", idempotency_key: SecureRandom.base36(16))
      schedule!
    end
  end
end
