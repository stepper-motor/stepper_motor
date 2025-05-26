# frozen_string_literal: true

class StepperMotorMigration005 < ActiveRecord::Migration[7.2]
  def change
    # Deduce whether the foreign key should be a UUID or not
    journey_id_column = StepperMotor::Journey.columns_hash.fetch("id")
    same_id_type_as_journey = journey_id_column.type

    create_table :stepper_motor_scheduled_tasks, id: same_id_type_as_journey do |t|
      t.references :journey, foreign_key: {to_table: "stepper_motor_journeys", on_delete: :cascade}
      t.datetime :scheduled_at
      t.string :idempotency_key, null: false
      t.string :active_job_id, null: true
      t.timestamps
    end

    add_index :stepper_motor_scheduled_tasks, [:journey_id, :idempotency_key], unique: true
  end
end
