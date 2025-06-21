# frozen_string_literal: true

module StepperMotor::TestHelper
  # Allows running a given Journey to completion, skipping across the waiting periods.
  # This is useful to evaluate all side effects of a Journey. The helper will ensure
  # that the number of steps performed is equal to the number of steps defined - this way
  # it will not enter into an endless loop. If, after completing all the steps, the journey
  # has neither canceled nor finished, an exception will be raised.
  #
  # @param journey[StepperMotor::Journey] the journey to speedrun
  # @param time_travel[Boolean] whether to use ActiveSupport time travel (default: true)
  #   Note: When time_travel is true, this method will permanently travel time forward
  #   and will not reset it back to the original time when the method exits.
  # @return void
  def speedrun_journey(journey, time_travel: true)
    journey.save!
    n_steps = journey.step_definitions.length
    n_steps.times do
      journey.reload
      break if journey.canceled? || journey.finished?

      if time_travel
        # Use time travel to move slightly ahead of the time when the next step should be performed
        next_step_time = journey.next_step_to_be_performed_at
        travel_to(next_step_time + 1.second)
      else
        # Update the journey's timestamp to bypass waiting periods
        journey.update(next_step_to_be_performed_at: Time.current)
      end
      journey.perform_next_step!
    end
    journey.reload
    journey_did_complete = journey.canceled? || journey.finished?
    raise "Journey #{journey} did not finish or cancel after performing #{n_steps} steps" unless journey_did_complete
  end

  # Performs the named step of the journey without waiting for the time to perform the step.
  #
  # @param journey[StepperMotor::Journey] the journey to speedrun
  # @param step_name[Symbol] the name of the step to run
  # @return void
  def immediately_perform_single_step(journey, step_name)
    journey.save!
    journey.update!(next_step_name: step_name, next_step_to_be_performed_at: Time.current)
    journey.perform_next_step!
  end
end
