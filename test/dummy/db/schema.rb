# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_06_09_221201) do
  create_table "stepper_motor_journeys", charset: "utf8mb4", collation: "utf8mb4_uca1400_ai_ci", force: :cascade do |t|
    t.string "type", null: false
    t.string "state", default: "ready"
    t.string "hero_type"
    t.bigint "hero_id"
    t.boolean "allow_multiple", default: false
    t.string "previous_step_name"
    t.string "next_step_name"
    t.datetime "next_step_to_be_performed_at"
    t.bigint "steps_entered", default: 0, null: false
    t.bigint "steps_completed", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "idempotency_key"
    t.virtual "journey_uniq_col_generated", type: :string, as: "case when `state` in ('ready','performing','paused') and `allow_multiple` = 0 and `type` is not null and `hero_id` is not null and `hero_type` is not null then concat(`type`,':',`hero_id`,':',`hero_type`) else NULL end", stored: true
    t.index ["hero_type", "hero_id"], name: "index_stepper_motor_journeys_on_hero_type_and_hero_id"
    t.index ["journey_uniq_col_generated"], name: "idx_journeys_one_per_hero_mysql_generated", unique: true
    t.index ["next_step_to_be_performed_at"], name: "index_stepper_motor_journeys_on_next_step_to_be_performed_at"
    t.index ["type", "hero_type", "hero_id"], name: "index_stepper_motor_journeys_on_type_and_hero_type_and_hero_id"
    t.index ["type"], name: "index_stepper_motor_journeys_on_type"
    t.index ["updated_at"], name: "index_stepper_motor_journeys_on_updated_at"
    t.index ["updated_at"], name: "stuck_journeys_index"
  end
end
