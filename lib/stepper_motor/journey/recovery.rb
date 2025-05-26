# frozen_string_literal: true

module StepperMotor::Journey::Recovery
  extend ActiveSupport::Concern

  included do
    # Allows querying for Journeys which are stuck in "performing" state since a certain
    # timestamp. These Journeys have likely been stuck because the worker that was performing
    # the step has crashed or was forcibly restarted.
    scope :stuck, ->(since) {
      where(updated_at: ..since).performing
    }

    # Sets the behavior when a Journey gets stuck in "performing" state. The default us "reattempt" -
    # it is going to try to restart the step the Journey got stuck on
    class_attribute :when_stuck, default: :reattempt, instance_accessor: false, instance_reader: true
  end

  def recover!
    case when_stuck
    when :reattempt
      with_lock do
        return unless performing?
        next_step = lookup_step_definition(next_step_name)
        set_next_step_and_enqueue(next_step, wait: 0)
      end
    else
      with_lock do
        return unless performing?
        canceled!
      end
    end
  end
end
