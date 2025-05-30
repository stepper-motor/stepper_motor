class StepperMotorMigration004 < ActiveRecord::Migration[7.2]
  def up
    quoted_false = connection.quote(false)
    add_index :stepper_motor_journeys, [:type, :hero_id, :hero_type], 
              where: "allow_multiple = '#{quoted_false}' AND state IN ('ready', 'performing', 'paused')", 
              unique: true, 
              name: :idx_journeys_one_per_hero_with_paused

    # Remove old indexes that only include 'ready' state
    remove_index :stepper_motor_journeys, [:type, :hero_id, :hero_type], name: :one_per_hero_index, where: "allow_multiple = '0' AND state IN ('ready', 'performing')", algorithm: :concurrently 
  end

  def down
    # Recreate old indexes
    quoted_false = connection.quote(false)
    add_index :stepper_motor_journeys, [:type, :hero_id, :hero_type], 
              where: "allow_multiple = '#{quoted_false}' AND state IN ('ready', 'performing')", 
              unique: true, 
              name: :one_per_hero_index

    # Remove new indexes
    remove_index :stepper_motor_journeys, name: :idx_journeys_one_per_hero_with_paused, algorithm: :concurrently
  end
end
