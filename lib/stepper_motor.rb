# frozen_string_literal: true

require_relative "stepper_motor/version"
require_relative "stepper_motor/railtie" if defined?(Rails::Railtie)
require "active_support"

module StepperMotor
  class Error < StandardError; end

  class JourneyNotPersisted < Error; end

  class StepConfigurationError < ArgumentError; end

  autoload :Journey, File.dirname(__FILE__) + "/stepper_motor/journey.rb"
  autoload :Step, File.dirname(__FILE__) + "/stepper_motor/step.rb"

  autoload :BaseJob, File.dirname(__FILE__) + "/stepper_motor/base_job.rb"
  autoload :PerformStepJob, File.dirname(__FILE__) + "/stepper_motor/perform_step_job.rb"
  autoload :PerformStepJobV2, File.dirname(__FILE__) + "/stepper_motor/perform_step_job.rb"
  autoload :HousekeepingJob, File.dirname(__FILE__) + "/stepper_motor/housekeeping_job.rb"
  autoload :DeleteCompletedJourneysJob, File.dirname(__FILE__) + "/stepper_motor/delete_completed_journeys_job.rb"
  autoload :RecoverStuckJourneysJob, File.dirname(__FILE__) + "/stepper_motor/recover_stuck_journeys_job.rb"
  autoload :RecoverStuckJourneysJobV1, File.dirname(__FILE__) + "/stepper_motor/recover_stuck_journeys_job.rb"

  autoload :InstallGenerator, File.dirname(__FILE__) + "/generators/install_generator.rb"
  autoload :ForwardScheduler, File.dirname(__FILE__) + "/stepper_motor/forward_scheduler.rb"
  autoload :CyclicScheduler, File.dirname(__FILE__) + "/stepper_motor/cyclic_scheduler.rb"
  autoload :TestHelper, File.dirname(__FILE__) + "/stepper_motor/test_helper.rb"

  mattr_accessor :scheduler, default: ForwardScheduler.new
  mattr_accessor :delete_completed_journeys_after, default: 30.days

  # Extends the BaseJob of the library with any additional options
  def self.extend_base_job(&blk)
    ActiveSupport::Reloader.to_prepare do
      BaseJob.class_eval(&blk)
    end
  end

  def self.wrap_conditional(cond, negate: false)
    callable = case cond
    when Array
      wrapped = cond.map {|e| wrap_conditional(e, negate: false) }
      Proc.new do |*a, **k|
        wrapped.all? {|e| e.call(*a, **k) }
      end
    when Symbol
      Proc.new { send(cond) ? true : false }
    else
      if cond.respond_to?(:call)
        Proc.new { cond.call ? true : false }
      else
        Proc.new { cond ? true : false }
      end
    end

    if negate
      Proc.new { |*a, **k| !callable.call(*a, **k) }
    else
      callable
    end
  end
end
