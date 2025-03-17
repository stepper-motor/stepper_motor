# frozen_string_literal: true

# Describes a step in a journey. These objects get stored inside the `step_definitions`
# array of the Journey subclass. When the step gets performed, the block passed to the
# constructor will be instance_exec'd with the Journey model being the context
class StepperMotor::Step
  attr_reader :name, :wait, :seq
  def initialize(name:, seq:, wait: 0, &step_block)
    @step_block = step_block
    @name = name.to_s
    @wait = wait
    @seq = seq
  end

  # Makes the Step object itself callable
  def to_proc
    @step_block
  end
end
