# frozen_string_literal: true

# The forward scheduler enqueues a job for every Journey that
# gets sent to the `#schedule`. The job is then stored in the queue
# and gets picked up by the ActiveJob worker normally. This is the simplest
# option if your ActiveJob adapter supports far-ahead scheduling. Some adapters,
# such as SQS, have limitations regarding the maximum delay after which a message
# will become visible. For SQS, the limit is 900 seconds. If the job is further in the future,
# it is likely going to fail to get enqueued. If you are working with a queue adapter
# either:
#
# * Does not allow easy introspection of jobs in the future (like Redis-based queues)
# * Limits the value of the `wait:` parameter
#
# this scheduler is not a good fit for you, and you will need to use the {CyclicScheduler} instead.
class StepperMotor::ForwardScheduler
  def schedule(journey)
    StepperMotor::PerformStepJobV2
      .set(wait_until: journey.next_step_to_be_performed_at)
      .perform_later(journey_id: journey.id, journey_class_name: journey.class.to_s)
  end
end
