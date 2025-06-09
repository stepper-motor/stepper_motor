class StepperMotorMigration005 < ActiveRecord::Migration[7.2]
  def up
    unless mysql?
      say "Skipping migration as it is only used with MySQL (mysql2 or trilogy)"
      return
    end

    # Add generated column that combines the state, type, hero_id, and hero_type
    # The column will be NULL if any of the components is NULL
    execute <<-SQL
      ALTER TABLE stepper_motor_journeys
      ADD COLUMN journey_uniq_col_generated VARCHAR(255) GENERATED ALWAYS AS (
        CASE 
          WHEN state IN ('ready', 'performing', 'paused') 
          AND allow_multiple = 0 
          AND type IS NOT NULL 
          AND hero_id IS NOT NULL 
          AND hero_type IS NOT NULL
          THEN CONCAT(type, ':', hero_id, ':', hero_type)
          ELSE NULL
        END
      ) STORED
    SQL

    # Add unique index on the generated column with MySQL-specific name
    add_index :stepper_motor_journeys, :journey_uniq_col_generated, 
              unique: true, 
              name: :idx_journeys_one_per_hero_mysql_generated

    # Remove old indexes that include 'ready', 'performing', and 'paused' states
    remove_index :stepper_motor_journeys, name: :idx_journeys_one_per_hero_with_paused
  end

  def down
    unless mysql?
      say "Skipping migration as it is only used with MySQL (mysql2 or trilogy)"
      return
    end

    # Remove the generated column and its index
    remove_index :stepper_motor_journeys, name: :idx_journeys_one_per_hero_mysql_generated
    remove_column :stepper_motor_journeys, :journey_uniq_col_generated

    # Recreate old indexes
    quoted_false = connection.quote(false)
    add_index :stepper_motor_journeys, [:type, :hero_id, :hero_type], 
              where: "allow_multiple = '#{quoted_false}' AND state IN ('ready', 'performing', 'paused')", 
              unique: true, 
              name: :idx_journeys_one_per_hero_with_paused
  end

  private

  def mysql?
    adapter = connection.adapter_name.downcase
    adapter == "mysql2" || adapter == "trilogy"
  end
end
