# All StepperMotor job classes inherit from this one. It is available for
# extension from StepperMotor.extend_base_job_class so that you can set
# priority, include and prepend modules and so forth.
class StepperMotor::BaseJob < ActiveJob::Base
end
