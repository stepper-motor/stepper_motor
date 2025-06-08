# frozen_string_literal: true

# Sets the scheduler. The ForwardScheduler will enqueue jobs for performing steps
# regardless of how far in the future a step needs to be taken. The CyclicScheduler
# will only enqueue jobs for steps which are to be performed soon. If you want to use
# the CyclicScheduler, you will need to configure it for the proper interval duration:
#
#   StepperMotor.scheduler = StepperMotor::CyclicScheduler.new(cycle_duration: 30.minutes)
#
# and add its cycle job into your recurring jobs table. For example, for solid_queue:
#
#   stepper_motor_houseleeping:
#     schedule: "*/30 * * * *" # Every 30 minutes
#     class: "StepperMotor::CyclicScheduler::RunSchedulingCycleJob"
#
# The cadence of the cyclic scheduler and the cadence of your cron job should be equal.
#
# If your queue is not susceptible to performance degradation with large numbers of
# "far future" jobs and allows scheduling "far ahead" - you can use the `ForwardScheduler`
# which is the default.
StepperMotor.scheduler = StepperMotor::ForwardScheduler.new

# Sets the amount of time after which completed (finished and canceled)
# Journeys are going to be deleted from the database. If you want to keep
# them in the database indefinitely, set this parameter to `nil`.
# To perform the actual cleanups, add the `StepperMotor::HousekeepingJob` to your
# recurring jobs table. For example, for solid_queue:
#
#   stepper_motor_housekeeping:
#     schedule: "*/30 * * * *" # Every 30 minutes
#     class: "StepperMotor::HousekeepingJob"
StepperMotor.delete_completed_journeys_after = 30.days

# Extends the base StepperMotor ActiveJob with any calls you would use to customise a
# job in your codebase. At the minimum, we recommend setting all StepperMotor job priorities
# to "high" - according to the priority denomination you are using.
# StepperMotor.extend_base_job do
#   queue_with_priority :high
#   discard_on ActiveRecord::NotFound
# end
