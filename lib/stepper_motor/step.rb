# frozen_string_literal: true

# Describes a step in a journey. These objects get stored inside the `step_definitions`
# array of the Journey subclass. When the step gets performed, the block passed to the
# constructor will be instance_exec'd with the Journey model being the context
class StepperMotor::Step
  class MissingDefinition < NoMethodError
  end

  attr_reader :name, :wait, :seq, :wrap
  def initialize(name:, seq:, wait: 0, &step_block)
    @step_block = step_block
    @name = name.to_s
    @wait = wait
    @seq = seq
  end

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
  end
end
