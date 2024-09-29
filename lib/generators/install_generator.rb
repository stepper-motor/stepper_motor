# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module StepperMotor
  # The generator is used to install StepperMotor. It adds an example Journey, a configing
  # initializer and the migration that creates tables.
  # Run it with +bin/rails g stepper_motor:install+ in your console.
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_paths << File.join(File.dirname(File.dirname(__FILE__)))

    class_option :database, type: :string, aliases: %i[--db], desc: "The database for your migration. By default, the current environment's primary database is used."
    class_option :hero_foreign_key_type, type: :string, aliases: %i[--fk], desc: "The foreign key type to use for hero_id. Can be either bigint or uuid"

    # Generates monolithic migration file that contains all database changes.
    def create_migration_file
      migration_template "generators/migration.rb.erb", File.join(db_migrate_path, "create_stepper_motor_tables.rb")
    end

    private

    def uuid_fk?
      options["hero_foreign_key_type"].to_s.downcase == "uuid"
    end

    def migration_version
      ActiveRecord::VERSION::STRING.split(".").take(2).join(".")
    end
  end
end
