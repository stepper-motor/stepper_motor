require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  module TestExtension
  end

  test "allows extending the base job" do
    ActiveSupport::Reloader.reload!

    refute StepperMotor::BaseJob.ancestors.include?(TestExtension)

    StepperMotor.extend_base_job { include TestExtension }
    ActiveSupport::Reloader.reload!

    assert StepperMotor::BaseJob.ancestors.include?(TestExtension)
  end
end
