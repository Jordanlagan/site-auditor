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

ActiveRecord::Schema[7.2].define(version: 2026_02_23_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "adaptive_tests", force: :cascade do |t|
    t.bigint "discovered_page_id", null: false
    t.string "test_type"
    t.string "decision_reason"
    t.jsonb "results"
    t.integer "impact_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discovered_page_id"], name: "index_adaptive_tests_on_discovered_page_id"
  end

  create_table "audit_issues", force: :cascade do |t|
    t.bigint "audit_id", null: false
    t.string "category", null: false
    t.string "severity", null: false
    t.string "title", null: false
    t.text "description"
    t.text "recommendation"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audit_id", "category"], name: "index_audit_issues_on_audit_id_and_category"
    t.index ["audit_id"], name: "index_audit_issues_on_audit_id"
    t.index ["category"], name: "index_audit_issues_on_category"
    t.index ["severity"], name: "index_audit_issues_on_severity"
  end

  create_table "audit_questions", force: :cascade do |t|
    t.bigint "audit_id", null: false
    t.bigint "discovered_page_id"
    t.string "question_type"
    t.text "question_text"
    t.jsonb "options"
    t.text "user_response"
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audit_id", "status"], name: "index_audit_questions_on_audit_id_and_status"
    t.index ["audit_id"], name: "index_audit_questions_on_audit_id"
    t.index ["discovered_page_id"], name: "index_audit_questions_on_discovered_page_id"
  end

  create_table "audits", force: :cascade do |t|
    t.string "url", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "current_phase"
    t.string "audit_mode", default: "single_page"
    t.jsonb "ai_config", default: {}
    t.integer "test_ids", default: [], array: true
    t.text "ai_summary"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["status"], name: "index_audits_on_status"
    t.index ["url"], name: "index_audits_on_url"
  end

  create_table "discovered_pages", force: :cascade do |t|
    t.bigint "audit_id", null: false
    t.string "url", null: false
    t.string "page_type"
    t.integer "priority_score"
    t.string "status", default: "pending"
    t.jsonb "crawl_metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "data_collection_status", default: "pending"
    t.string "testing_status", default: "pending"
    t.boolean "is_priority_page", default: false
    t.index ["audit_id", "data_collection_status"], name: "index_discovered_pages_on_audit_id_and_data_collection_status"
    t.index ["audit_id", "is_priority_page"], name: "index_discovered_pages_on_audit_id_and_is_priority_page"
    t.index ["audit_id", "page_type"], name: "index_discovered_pages_on_audit_id_and_page_type"
    t.index ["audit_id", "priority_score"], name: "index_discovered_pages_on_audit_id_and_priority_score"
    t.index ["audit_id", "testing_status"], name: "index_discovered_pages_on_audit_id_and_testing_status"
    t.index ["audit_id"], name: "index_discovered_pages_on_audit_id"
  end

  create_table "page_data", force: :cascade do |t|
    t.bigint "discovered_page_id", null: false
    t.jsonb "fonts", default: []
    t.jsonb "colors", default: []
    t.jsonb "images", default: []
    t.jsonb "scripts", default: []
    t.jsonb "stylesheets", default: []
    t.integer "total_page_weight_bytes"
    t.jsonb "asset_distribution"
    t.jsonb "performance_metrics"
    t.jsonb "headings"
    t.text "page_content"
    t.jsonb "links"
    t.string "meta_title"
    t.text "meta_description"
    t.jsonb "meta_tags"
    t.jsonb "structured_data"
    t.jsonb "screenshots"
    t.text "html_content"
    t.text "computed_styles"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discovered_page_id"], name: "index_page_data_on_discovered_page_id"
  end

  create_table "page_screenshots", force: :cascade do |t|
    t.bigint "discovered_page_id", null: false
    t.string "device_type"
    t.string "screenshot_url"
    t.integer "viewport_width"
    t.integer "viewport_height"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discovered_page_id"], name: "index_page_screenshots_on_discovered_page_id"
  end

  create_table "test_groups", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "color", default: "#6366f1"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_test_groups_on_name", unique: true
  end

  create_table "test_results", force: :cascade do |t|
    t.bigint "discovered_page_id", null: false
    t.bigint "audit_id", null: false
    t.string "test_key", null: false
    t.string "test_category"
    t.string "status", null: false
    t.text "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "ai_prompt"
    t.jsonb "data_context", default: {}
    t.text "ai_response"
    t.jsonb "details", default: []
    t.index ["audit_id", "status"], name: "index_test_results_on_audit_id_and_status"
    t.index ["audit_id", "test_category"], name: "index_test_results_on_audit_id_and_test_category"
    t.index ["audit_id"], name: "index_test_results_on_audit_id"
    t.index ["discovered_page_id", "test_key"], name: "index_test_results_on_discovered_page_id_and_test_key", unique: true
    t.index ["discovered_page_id"], name: "index_test_results_on_discovered_page_id"
  end

  create_table "tests", force: :cascade do |t|
    t.bigint "test_group_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "test_key", null: false
    t.text "test_details", null: false
    t.jsonb "data_sources", default: [], null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_tests_on_active"
    t.index ["test_group_id"], name: "index_tests_on_test_group_id"
    t.index ["test_key"], name: "index_tests_on_test_key", unique: true
  end

  create_table "wireframes", force: :cascade do |t|
    t.bigint "audit_id", null: false
    t.string "title", null: false
    t.string "file_path", null: false
    t.jsonb "config_used", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audit_id"], name: "index_wireframes_on_audit_id"
    t.index ["created_at"], name: "index_wireframes_on_created_at"
  end

  add_foreign_key "adaptive_tests", "discovered_pages"
  add_foreign_key "audit_issues", "audits"
  add_foreign_key "audit_questions", "audits"
  add_foreign_key "audit_questions", "discovered_pages"
  add_foreign_key "discovered_pages", "audits"
  add_foreign_key "page_data", "discovered_pages"
  add_foreign_key "page_screenshots", "discovered_pages"
  add_foreign_key "test_results", "audits"
  add_foreign_key "test_results", "discovered_pages"
  add_foreign_key "tests", "test_groups"
  add_foreign_key "wireframes", "audits"
end
