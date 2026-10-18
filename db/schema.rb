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

ActiveRecord::Schema[8.1].define(version: 2026_10_18_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "analyses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.string "source", default: "upload", null: false
    t.string "filename"
    t.text "error_message"
    t.jsonb "result"
    t.integer "entries_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_analyses_on_created_at"
    t.index ["status"], name: "index_analyses_on_status"
  end

  create_table "domain_categories", force: :cascade do |t|
    t.string "domain", null: false
    t.string "category", null: false
    t.string "source", default: "ai", null: false
    t.float "confidence"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_domain_categories_on_domain", unique: true
  end

  create_table "shared_reports", force: :cascade do |t|
    t.string "token", null: false
    t.jsonb "data", default: {}, null: false
    t.string "delete_token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_shared_reports_on_expires_at"
    t.index ["token"], name: "index_shared_reports_on_token", unique: true
  end
end
