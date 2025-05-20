# frozen_string_literal: true

require_relative "lib/stepper_motor/version"

Gem::Specification.new do |spec|
  spec.name = "stepper_motor"
  spec.version = StepperMotor::VERSION
  spec.authors = ["Julik Tarkhanov"]
  spec.email = ["me@julik.nl"]
  spec.license = "LGPL"

  spec.summary = "Effortless step workflows that embed nicely inside Rails"
  spec.description = "Step workflows for Rails/ActiveRecord"
  spec.homepage = "https://steppermotor.dev"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/stepper-motor/stepper_motor"
  spec.metadata["changelog_uri"] = "https://github.com/stepper-motor/stepper_motor/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      File.basename(f).start_with?(".")
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7"
  spec.add_dependency "activejob"
  spec.add_dependency "railties"
  spec.add_dependency "globalid"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rails", "~> 7.0"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "magic_frozen_string_literal"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "redcarpet" # needed for the yard gem to enable Github Flavored Markdown
  spec.add_development_dependency "sord"
end
