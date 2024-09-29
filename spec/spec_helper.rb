# frozen_string_literal: true

require "stepper_motor"
require "active_support/testing/time_helpers"
require "active_record"

module StepperMotorRailtieTestHelpers
  def establish_test_connection
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: "test.sqlite3")
    StepperMotor::InstallGenerator.source_root(File.dirname(__FILE__) + "/../../lib")
  end

  def fake_app_root
    File.dirname(__FILE__) + "/app"
  end

  def run_generator
    generator =  StepperMotor::InstallGenerator.new
    generator.destination_root = fake_app_root
    generator.create_migration_file
  end

  def run_migrations
    # Before running the migrations we need to require the migration files, since there is no
    # "full" Rails environment available
    Dir.glob(fake_app_root + "/db/migrate/*.rb").sort.each do |migration_file_path|
      warn migration_file_path
      require migration_file_path
    end

    ActiveRecord::Tasks::DatabaseTasks.root = fake_app_root
    ActiveRecord::Tasks::DatabaseTasks.migrate
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include ActiveSupport::Testing::TimeHelpers
  config.include StepperMotorRailtieTestHelpers
end
