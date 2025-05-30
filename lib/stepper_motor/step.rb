# frozen_string_literal: true

# Describes a step in a journey. These objects get stored inside the `step_definitions`
# array of the Journey subclass. When the step gets performed, the block passed to the
# constructor will be instance_exec'd with the Journey model being the context
class StepperMotor::Step
  class MissingDefinition < NoMethodError
  end

  # @return [String] the name of the step or method to call on the Journey
  attr_reader :name

  # @return [Numeric,ActiveSupport::Duration] how long to wait before performing the step
  attr_reader :wait

  # @private
  attr_reader :seq

  # Creates a new step definition
  #
  # @param name[String,Symbol] the name of the Step
  # @param wait[Numeric,ActiveSupport::Duration] the amount of time to wait before entering the step
  # @param on_exception[Symbol] the action to take if an exception occurs when performing the step.
  #   The possible values are:
  #   * `:cancel!` - cancels the Journey and re-raises the exception.
  #   * `:reattempt!` - reattempts the Journey and re-raises the exception.
  #   * `:pause!` - pauses the Journey for investigation and re-raises the exception.
  #   The Journey will be persisted before re-raising the exception in all these cases.
  def initialize(name:, seq:, on_exception:, wait: 0, &step_block)
    @step_block = step_block
    @name = name.to_s
    @wait = wait
    @seq = seq
    @on_exception = on_exception # TODO: Validate?
  end

  # Performs the step on the passed Journey, wrapping the step with the required context.
  #
  # @param journey[StepperMotor::Journey] the journey to perform the step in. If a `step_block`
  #   is passed in, it is going to be executed in the context of the journey using `instance_exec`.
  #   If only the name of the step has been provided, an accordingly named public method on the
  #   journey will be called
  # @return void
  def perform_in_context_of(journey)
    # This is a tricky bit.
    #
    # reattempt!, cancel! (and potentially - future flow control methods) all use `throw` to
    # immediately hop out of the perform block. They all use the same symbol thrown - :abort_step.
    # Nothing after `reattempt!` and `cancel!` in the same scope will run because of that `throw` -
    # not even the `rescue` clauses, so we need to catch here instead of the `perform_next_step!`
    # method. This way, if the step raises an exception, we can still let Journey flow control methods
    # be used, but we can capture the exception. Moreover: we need to be able to _call_ those methods from
    # within the rescue() clauses. So:
    catch(:abort_step) do
      if @step_block
        journey.instance_exec(&@step_block)
      elsif journey.respond_to?(name)
        journey.public_send(name) # TODO: context/params?
      else
        raise MissingDefinition.new(<<~MSG, name, _args = nil, _private = false, receiver: journey)
          No block or method to use for step `#{name}' on #{journey.class}
        MSG
      end
    end
  rescue MissingDefinition
    # This journey won't succeed with any number of reattempts, cancel it. Cancellation also will throw.
    catch(:abort_step) { journey.pause! }
    raise
  rescue => e
    # Act according to the set policy. The basic 2 for the moment are :reattempt! and :cancel!,
    # and can be applied by just calling the methods on the passed journey
    case @on_exception
    when :reattempt!
      catch(:abort_step) { journey.reattempt! }
    when :cancel!
      catch(:abort_step) { journey.cancel! }
    when :pause!
      catch(:abort_step) { journey.pause! }
    else
      # Leave the journey hanging in the "performing" state
    end

    # Re-raise the exception so that the Rails error handling can register it
    raise e
  end
end
