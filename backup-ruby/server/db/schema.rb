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

ActiveRecord::Schema[7.2].define(version: 2023_12_13_000000) do
  create_table "comparison_candidates", force: :cascade do |t|
    t.integer "source_file_id"
    t.integer "project_target_id"
    t.string "file_path"
    t.float "similarity_score"
    t.integer "rank"
    t.integer "width"
    t.integer "height"
    t.index ["project_target_id"], name: "index_comparison_candidates_on_project_target_id"
    t.index ["source_file_id"], name: "index_comparison_candidates_on_source_file_id"
  end

  create_table "project_targets", force: :cascade do |t|
    t.integer "project_id"
    t.string "name"
    t.string "path"
    t.index ["project_id"], name: "index_project_targets_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name"
    t.string "source_path"
    t.string "status", default: "pending"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "source_confirmations", force: :cascade do |t|
    t.integer "source_file_id", null: false
    t.boolean "confirmed", default: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_file_id"], name: "index_source_confirmations_on_source_file_id", unique: true
  end

  create_table "source_files", force: :cascade do |t|
    t.integer "project_id"
    t.string "relative_path"
    t.string "full_path"
    t.integer "width"
    t.integer "height"
    t.integer "size_bytes"
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "aspect_ratio"
    t.integer "area"
    t.text "phash"
    t.text "ahash"
    t.text "dhash"
    t.text "histogram"
    t.index ["area"], name: "index_source_files_on_area"
    t.index ["aspect_ratio"], name: "index_source_files_on_aspect_ratio"
    t.index ["project_id", "relative_path"], name: "index_source_files_on_project_id_and_relative_path"
    t.index ["project_id"], name: "index_source_files_on_project_id"
  end

  create_table "target_files", force: :cascade do |t|
    t.integer "project_target_id"
    t.string "full_path", null: false
    t.string "relative_path", null: false
    t.integer "width"
    t.integer "height"
    t.integer "size_bytes"
    t.float "aspect_ratio"
    t.integer "area"
    t.text "phash"
    t.text "ahash"
    t.text "dhash"
    t.text "histogram"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["area"], name: "index_target_files_on_area"
    t.index ["aspect_ratio"], name: "index_target_files_on_aspect_ratio"
    t.index ["project_target_id", "relative_path"], name: "index_target_files_on_project_target_id_and_relative_path"
    t.index ["project_target_id"], name: "index_target_files_on_project_target_id"
  end

  create_table "target_selections", force: :cascade do |t|
    t.integer "source_file_id", null: false
    t.integer "project_target_id", null: false
    t.integer "selected_candidate_id"
    t.boolean "no_match", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["selected_candidate_id"], name: "index_target_selections_on_selected_candidate_id"
    t.index ["source_file_id", "project_target_id"], name: "index_target_selections_on_source_and_target", unique: true
  end

  add_foreign_key "comparison_candidates", "project_targets"
  add_foreign_key "comparison_candidates", "source_files"
  add_foreign_key "project_targets", "projects"
  add_foreign_key "source_confirmations", "source_files"
  add_foreign_key "source_files", "projects"
  add_foreign_key "target_files", "project_targets"
  add_foreign_key "target_selections", "comparison_candidates", column: "selected_candidate_id"
  add_foreign_key "target_selections", "project_targets"
  add_foreign_key "target_selections", "source_files"
end
