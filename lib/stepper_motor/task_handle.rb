# frozen_string_literal: true

class StepperMotor::TaskHandle < ActiveRecord::Base
  self.table_name = "stepper_motor_task_handles"
  belongs_to :journey, class_name: "StepperMotor::Journey"
end
