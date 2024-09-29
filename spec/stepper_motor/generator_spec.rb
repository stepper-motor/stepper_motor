require_relative "../spec_helper"

RSpec.describe "StepperMotor::InstallGenerator" do
  it "is able to set up a test database" do
    establish_test_connection
    expect {
      run_generator
      run_migrations
    }.not_to raise_error
  end

  after(:each) do
    FileUtils.rm_rf(fake_app_root)
  end
end
