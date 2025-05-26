# frozen_string_literal: true

class StepperMotor::ScheduledTask < ActiveRecord::Base
  self.table_name = "stepper_motor_scheduled_tasks"
  belongs_to :journey, class_name: "StepperMotor::Journey"
end
