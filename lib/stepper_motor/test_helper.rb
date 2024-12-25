module StepperMotor::TestHelper
  # Allows running a given Journey to completion, skipping across the waiting periods.
  # This is useful to evaluate all side effects of a Journey. The helper will ensure
  # that the number of steps performed is equal to the number of steps defined - this way
  # it will not enter into an endless loop. If, after completing all the steps, the journey
  # has neither canceled nor finished, an exception will be raised.
  #
  # @param journey[StepperMotor::Journey] the journey to speedrun
  # @return void
  def speedrun_stepper_motor_journey(journey)
    journey.save!
    n_steps = journey.step_definitions.length
    n_steps.times do
      journey.reload
      break if journey.canceled? || journey.finished?
      journey.update(next_step_to_be_performed_at: Time.current)
      journey.perform_next_step!
    end
    journey.reload
    journey_did_complete = journey.canceled? || journey.finished?
    raise "Journey #{journey} did not finish or cancel after performing #{n_steps} steps" unless journey_did_complete
  end
end
