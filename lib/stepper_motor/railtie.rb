# frozen_string_literal: true

module StepperMotor
  class Railtie < ::Rails::Railtie
    rake_tasks do
      # none for now
    end

    generators do
      require "generators/install_generator"
    end

    # The `to_prepare` block which is executed once in production
    # and before each request in development.
    config.to_prepare do
      # none for now
    end
  end
end
