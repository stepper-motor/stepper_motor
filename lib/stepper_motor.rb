# frozen_string_literal: true

require_relative "stepper_motor/version"
require "active_support"

module StepperMotor
  class Error < StandardError; end

  class JourneyNotPersisted < Error; end

  autoload :Journey, File.dirname(__FILE__) + "/stepper_motor/journey.rb"
  autoload :Step, File.dirname(__FILE__) + "/stepper_motor/step.rb"
  autoload :PerformStepJob, File.dirname(__FILE__) + "/stepper_motor/perform_step_job.rb"
  autoload :InstallGenerator, File.dirname(__FILE__) + "/generators/install_generator.rb"
  autoload :ForwardScheduler, File.dirname(__FILE__) + "/stepper_motor/forward_scheduler.rb"
  autoload :CyclicScheduler, File.dirname(__FILE__) + "/stepper_motor/cyclic_scheduler.rb"

  mattr_accessor :scheduler, default: ForwardScheduler.new
end
