# frozen_string_literal: true

class StepperMotorMigration002 < ActiveRecord::Migration[7.2]
  def change
    # An index is needed to recover stuck journeys
    add_index :stepper_motor_journeys, [:updated_at], name: "stuck_journeys_index", where: "state = 'performing'"
  end
end
