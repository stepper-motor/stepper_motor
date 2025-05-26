# frozen_string_literal: true

class StepperMotorMigration003 < ActiveRecord::Migration[7.2]
  def change
    add_column :stepper_motor_journeys, :idempotency_key, :string, null: true
  end
end
 