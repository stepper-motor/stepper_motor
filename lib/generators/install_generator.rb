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
    class_option :uuid, type: :boolean, desc: "The foreign key type to use for hero_id. Can be either bigint or uuid"

    # Generates monolithic migration file that contains all database changes.
    def create_migration_file
      # Migration files are named "...migration_001.rb" etc. This allows them to be emitted
      # as they get added, and the order of the migrations can be controlled using predictable sorting.
      # Adding a new migration to the gem is then just adding a file.
      migration_file_paths_in_order = Dir.glob(__dir__ + "/*_migration_*.rb.erb").sort
      migration_file_paths_in_order.each do |migration_template_path|
        untemplated_migration_filename = File.basename(migration_template_path).gsub(/\.erb$/, "")
        migration_template(migration_template_path, File.join(db_migrate_path, untemplated_migration_filename))
      end
    end

    private

    def uuid_fk?
      options["uuid"].present?
    end

    def migration_version
      ActiveRecord::VERSION::STRING.split(".").take(2).join(".")
    end
  end
end
