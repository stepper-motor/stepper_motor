require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  test "allows extending the base job" do
    retrieved_name = StepperMotor.extend_base_job { name }
    assert_equal "StepperMotor::BaseJob", retrieved_name
  end
end
