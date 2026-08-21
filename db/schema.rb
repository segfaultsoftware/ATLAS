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

ActiveRecord::Schema[8.1].define(version: 2026_08_20_000000) do
  create_table "celestial_bodies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_celestial_bodies_on_name", unique: true
  end

  create_table "celestial_transits", force: :cascade do |t|
    t.integer "celestial_body_id", null: false
    t.float "celestial_coordinates_start_x", null: false
    t.float "celestial_coordinates_start_y", null: false
    t.float "celestial_coordinates_target_x", null: false
    t.float "celestial_coordinates_target_y", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["celestial_body_id"], name: "index_celestial_transits_on_celestial_body_id", unique: true
  end

  create_table "games", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", limit: 64, null: false
    t.integer "profile_id", null: false
    t.integer "randomization_seed", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id"], name: "index_games_on_profile_id"
    t.check_constraint "name = trim(name) AND length(name) BETWEEN 1 AND 64", name: "games_name_is_trimmed_and_bounded"
    t.check_constraint "randomization_seed BETWEEN 0 AND 4294967295", name: "games_randomization_seed_is_unsigned_32_bit"
  end

  create_table "manual_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_manual_categories_on_slug", unique: true
  end

  create_table "manual_page_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "manual_category_id", null: false
    t.integer "manual_page_id", null: false
    t.datetime "updated_at", null: false
    t.index ["manual_category_id"], name: "index_manual_page_categories_on_manual_category_id"
    t.index ["manual_page_id", "manual_category_id"], name: "index_manual_page_categories_on_page_and_category", unique: true
    t.index ["manual_page_id"], name: "index_manual_page_categories_on_manual_page_id"
  end

  create_table "manual_pages", force: :cascade do |t|
    t.text "content", default: "", null: false
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_manual_pages_on_parent_id"
    t.index ["slug"], name: "index_manual_pages_on_slug", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.string "avatar_key"
    t.datetime "created_at", null: false
    t.string "preferred_name"
    t.string "preferred_playtimes", limit: 256
    t.string "pronouns"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_profiles_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.string "remember_token"
    t.string "role", default: "user", null: false
    t.datetime "updated_at", null: false
    t.index "LOWER(email)", name: "index_users_on_lower_email", unique: true
    t.index ["remember_token"], name: "index_users_on_remember_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "celestial_transits", "celestial_bodies"
  add_foreign_key "games", "profiles"
  add_foreign_key "manual_page_categories", "manual_categories"
  add_foreign_key "manual_page_categories", "manual_pages"
  add_foreign_key "manual_pages", "manual_pages", column: "parent_id"
  add_foreign_key "profiles", "users"
end
