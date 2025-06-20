# typed: strong
# StepperMotor is a module for building multi-step flows where steps are sequential and only
# ever progress forward. The building block of StepperMotor is StepperMotor::Journey
module StepperMotor
  VERSION = T.let("0.1.17", T.untyped)
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
  end
end
