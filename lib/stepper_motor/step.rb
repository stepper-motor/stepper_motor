# frozen_string_literal: true

# Describes a step in a journey. These objects get stored inside the `step_definitions`
# array of the Journey subclass. When the step gets performed, the block passed to the
# constructor will be instance_exec'd with the Journey model being the context
class StepperMotor::Step
  class MissingDefinition < NoMethodError
  end

  attr_reader :name, :wait, :seq, :wrap
  def initialize(name:, seq:, wait: 0, on_exception: :reattempt!, &step_block)
    @step_block = step_block
    @name = name.to_s
    @wait = wait
    @seq = seq
    @on_exception = on_exception # TODO: Validate?
  end
    
  # @param journey[StepperMotor::Journey] the journey to perform the step in. If a `step_block`
  #   is passed in, it is going to be executed in the context of the journey using `instance_exec`.
  #   If only the name of the step has been provided, an accordingly named public method on the
  #   journey will be called
  # @return void
  def perform_in_context_of(journey)
    if @step_block
      journey.instance_exec(&@step_block)
    elsif journey.respond_to?(name)
      journey.public_send(name) # TODO: context/params?
    else
      raise MissingDefinition.new(<<~MSG, name, _args = nil, _private = false, receiver: journey)
        No block or method to use for step `#{name}' on #{journey.class}
      MSG
    end
  rescue MissingDefinition
    # This journey won't succeed with any number of reattempts, cancel it
    journey.cancel!
    raise
  rescue
    # Act according to the set policy. The basic 2 for the moment are :reattempt! and :cancel!,
    # and can be applied by just calling the methods on the passed journey
    case @on_exception
    when :reattempt!
      journey.reattempt!
    when :cancel!
      journey.cancel!
    else
      # Do nothing, which will leave the journey in the "performing" state
    end

    # Re-raise the exception so that the Rails error handling can register it
    raise
  end
end
