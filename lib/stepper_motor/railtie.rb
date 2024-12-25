# frozen_string_literal: true

module StepperMotor
  UNINITIALISED_DATABASE_EXCEPTIONS = [
    ActiveRecord::NoDatabaseError,
    ActiveRecord::StatementInvalid,
    ActiveRecord::ConnectionNotEstablished
  ]

  class Railtie < Rails::Railtie
    rake_tasks do
      task preload: :setup do
        if defined?(Rails) && Rails.respond_to?(:application)
          if Rails.application.config.eager_load
            ActiveSupport.run_load_hooks(:before_eager_load, Rails.application)
            Rails.application.config.eager_load_namespaces.each(&:eager_load!)
          end
        end
      end
    end

    generators do
      require "generators/install_generator"
    end

    # The `to_prepare` block which is executed once in production
    # and before each request in development.
    config.to_prepare do
      if defined?(Rails) && Rails.respond_to?(:application)
        _config_from_rails = Rails.application.config.try(:gouda)
        # if config_from_rails
        #  StepperMotor.config.scheduling_mode = config_from_rails[:scheduling_mode]
        # end
      else
        # Set default configuration
      end

      begin
        # Perform any tasks which touch the database here
      rescue *StepperMotor::UNINITIALISED_DATABASE_EXCEPTIONS
        # Do nothing. On a freshly checked-out Rails app, running even unrelated Rails tasks
        # (such as asset compilation) - or, more importantly, initial db:create -
        # will cause a NoDatabaseError, as this is a chicken-and-egg problem. That error
        # is safe to ignore in this instance - we should let the outer task proceed,
        # because if there is no database we should allow it to get created.
      end
    end
  end
end
