# frozen_string_literal: true

# The TaskHandle represents a persistent record of a scheduled step execution within a Journey.
# Unlike a standard ActiveJob, which only exists transiently in the job queue, TaskHandle provides
# a robust persistence layer that maintains scheduled steps even if the job queue is cleared.
# It enables comprehensive state tracking and monitoring of step execution status and timing,
# while providing built-in recovery capabilities for stuck or failed steps. The TaskHandle
# coordinates with its parent Journey for orchestration and maintains a complete audit trail
# of execution attempts and timing.
#
# Most importantly, TaskHandle implements the "transactional outbox" pattern - it ensures that
# step scheduling is atomic with the Journey's database transaction. This solves the fundamental
# issue where an ActiveJob enqueued during a transaction might not actually get committed if the
# transaction rolls back, leading to lost or inconsistent state. By persisting the TaskHandle
# within the same transaction as the Journey update, we guarantee that either both succeed or
# both fail.
#
# While ActiveJob is used internally for the actual execution (via PerformStepJob),
# the TaskHandle adds the crucial persistence layer needed for reliable multi-step
# process orchestration, especially for long-running journeys that may span days or weeks.
class StepperMotor::TaskHandle < ActiveRecord::Base
  self.table_name = "stepper_motor_task_handles"
  belongs_to :journey, class_name: "StepperMotor::Journey"
end
