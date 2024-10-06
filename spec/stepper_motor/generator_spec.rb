require_relative "../spec_helper"

RSpec.describe "StepperMotor::InstallGenerator" do
  it "is able to set up a test database" do
    expect {
      establish_test_connection
      run_generator
      run_migrations
    }.not_to raise_error
    expect(ActiveRecord::Base.connection.tables).to include("stepper_motor_journeys")
  ensure
    FileUtils.rm_rf(fake_app_root)
  end
end
