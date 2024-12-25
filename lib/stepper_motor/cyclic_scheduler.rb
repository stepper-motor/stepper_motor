# The cyclic scheduler is designed to be run regularly via a cron job. On every
# cycle, it is going to look for Journeys which are going to come up for step execution
# before the next cycle is supposed to run. Then it is going to enqueue jobs to perform
# steps on those journeys. Since the scheduler gets run at a discrete interval, but we
# still them to be processed on time, if we only picked up the journeys which have the
# step execution time set to now or earlier, we will always have delays. This is why
# this scheduler enqueues jobs for journeys whose time to run is between now and the
# next cycle.
#
# Once the job gets created, it then gets enqueued and gets picked up by the ActiveJob
# worker normally. If you are using SQS, which has a limit of 900 seconds for the `wait:`
# value, you need to run the scheduler at least (!) every 900 seconds, and preferably
# more frequently (for example, once every 5 minutes). This scheduler is also going to be
# more gentle with ActiveJob adapters that may get slower with large queue depths, such as
# good_job. This scheduler is a good fit if you are using an ActiveJob adapter which:
#
# * Does not allow easy introspection of jobs in the future (like Redis-based queues)
# * Limits the value of the `wait:` parameter
#
# The scheduler needs to be configured in your cron table.
class StepperMotor::CyclicScheduler < StepperMotor::ForwardScheduler
  class RunSchedulingCycleJob < ActiveJob::Base
    def perform
      scheduler = StepperMotor.scheduler
      return unless scheduler.is_a?(StepperMotor::CyclicScheduler)
      scheduler.run_scheduling_cycle
    end
  end

  # Creates a new scheduler. The scheduler needs to know how frequently it is going to be running -
  # you define that frequency when you configure your cron job that calls `run_scheduling_cycle`. Journeys which
  # have to perform their steps between the runs of the cycles will generate jobs. The more frequent the scheduling
  # cycle, the fewer jobs are going to be created per cycle.
  #
  # @param cycle_duration[ActiveSupport::Duration] how frequently the scheduler runs
  def initialize(cycle_duration:)
    @cycle_duration = cycle_duration
  end

  # Run a scheduling cycle. This should be called from your ActiveJob that runs on a regular Cron cadence. Ideally you
  # would call the instance of the scheduler configured for the whole StepperMotor (so that the `cycle_duration` gets
  # correctly applied, as it is necessary to pick the journeys to step). Normally, you would do this:
  #
  # @return [void]
  def run_scheduling_cycle
    # Find all the journeys that have to step before the next scheduling cycle. This also picks up journeys
    # which haven't been scheduled or weren't scheduled on time. We don't want to only schedule
    # journeys which are "past due", because this would make the timing of the steps very lax.
    scope = StepperMotor::Journey.where("state = 'ready' AND next_step_name IS NOT NULL AND next_step_to_be_performed_at < ?", Time.current + @cycle_duration)
    scope.find_each do |journey|
      schedule(journey)
    end
  end

  def schedule(journey)
    # We assume that the previous `run_scheduling_cycle` has occured recently. The longest time it will take
    # until the next `run_scheduling_cycle` is the duration of the cycle (`run_scheduling_cycle` did run
    # just before `schedule` gets called). Therefore, it should be sufficient to assume that if the step
    # has to run before the next `run_scheduling_cycle`, we have to schedule a job for it right now.
    time_remaining = journey.next_step_to_be_performed_at - Time.current
    super if time_remaining <= @cycle_duration
  end
end
