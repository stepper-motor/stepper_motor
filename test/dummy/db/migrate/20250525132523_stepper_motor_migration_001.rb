class StepperMotorMigration001 < ActiveRecord::Migration[7.2]
  def change
    
    create_table :stepper_motor_journeys do |t|
    
      t.string :type, null: false, index: true
      t.string :state, default: "ready"
      t.string :hero_type, null: true
      
      t.bigint :hero_id
      
      t.boolean :allow_multiple, default: false
      t.string :previous_step_name
      t.string :next_step_name
      t.datetime :next_step_to_be_performed_at
      t.bigint :steps_entered, default: 0, null: false
      t.bigint :steps_completed, default: 0, null: false
      t.timestamps
    end
    # Foreign key needs to be indexed for rapid lookups of journeys for a specific hero
    add_index :stepper_motor_journeys, [:hero_type, :hero_id]

    # An index is needed on the type/hero as well to check whether there is a journey
    # for a specific hero of a specific class
    add_index :stepper_motor_journeys, [:type, :hero_type, :hero_id]

    # A unique index prevents multiple journeys of the same type from being created for a particular hero
    quoted_false = connection.quote(false)
    add_index :stepper_motor_journeys, [:type, :hero_id, :hero_type], where: "allow_multiple = '#{quoted_false}' AND state IN ('ready', 'performing')", unique: true, name: :one_per_hero_index

    # An index is also needed for cleaning up finished and canceled journeys quickly
    # for a specific hero of a specific class
    add_index :stepper_motor_journeys, [:updated_at], where: "state = 'canceled' OR state = 'finished'"

    # An extra index is needed to speed up select-to-perform in case of central scheduling
    add_index :stepper_motor_journeys, [:next_step_to_be_performed_at], where: "state = 'ready'"
  end
end
