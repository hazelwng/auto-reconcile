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

ActiveRecord::Schema[8.1].define(version: 2026_05_13_045309) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "payload", default: {}, null: false
    t.bigint "target_id"
    t.string "target_type"
    t.string "user_agent"
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["target_type", "target_id"], name: "index_audit_events_on_target_type_and_target_id"
    t.index ["user_id"], name: "index_audit_events_on_user_id"
    t.index ["workspace_id"], name: "index_audit_events_on_workspace_id"
  end

  create_table "bank_transactions", force: :cascade do |t|
    t.bigint "balance_after_cents"
    t.string "balance_after_currency"
    t.string "check_number"
    t.string "counterparty"
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.text "memo"
    t.date "posted_date", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.string "txn_type", null: false
    t.datetime "updated_at", null: false
    t.date "value_date"
    t.bigint "workspace_id", null: false
    t.index ["discarded_at"], name: "index_bank_transactions_on_discarded_at"
    t.index ["workspace_id"], name: "index_bank_transactions_on_workspace_id"
  end

  create_table "data_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.datetime "discarded_at"
    t.string "kind", null: false
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.jsonb "schema_mapping", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["discarded_at"], name: "index_data_sources_on_discarded_at"
    t.index ["workspace_id"], name: "index_data_sources_on_workspace_id"
  end

  create_table "import_batches", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "data_source_id", null: false
    t.integer "duplicate_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.jsonb "error_log", default: [], null: false
    t.integer "processed_count", default: 0, null: false
    t.integer "row_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "success_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["data_source_id"], name: "index_import_batches_on_data_source_id"
    t.index ["user_id"], name: "index_import_batches_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.datetime "discarded_at"
    t.date "due_date"
    t.string "invoice_number", null: false
    t.date "issue_date", null: false
    t.text "notes"
    t.string "payer"
    t.string "status", default: "open", null: false
    t.bigint "total_cents", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["discarded_at"], name: "index_invoices_on_discarded_at"
    t.index ["workspace_id", "invoice_number"], name: "index_invoices_on_workspace_id_and_invoice_number", unique: true
    t.index ["workspace_id"], name: "index_invoices_on_workspace_id"
  end

  create_table "match_legs", force: :cascade do |t|
    t.bigint "allocated_amount_cents", null: false
    t.string "allocated_currency", default: "USD", null: false
    t.datetime "created_at", null: false
    t.bigint "match_id", null: false
    t.bigint "reconcilable_item_id", null: false
    t.string "side", null: false
    t.datetime "updated_at", null: false
    t.index ["match_id", "reconcilable_item_id"], name: "index_match_legs_on_match_id_and_reconcilable_item_id", unique: true
    t.index ["match_id"], name: "index_match_legs_on_match_id"
    t.index ["reconcilable_item_id"], name: "index_match_legs_on_reconcilable_item_id"
  end

  create_table "matches", force: :cascade do |t|
    t.decimal "confidence", precision: 5, scale: 4, default: "0.0", null: false
    t.datetime "confirmed_at"
    t.bigint "confirmed_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "discarded_at"
    t.string "method", null: false
    t.text "reasoning"
    t.bigint "reconciliation_run_id", null: false
    t.string "rejected_reason"
    t.string "status", default: "proposed", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["confirmed_by_user_id"], name: "index_matches_on_confirmed_by_user_id"
    t.index ["discarded_at"], name: "index_matches_on_discarded_at"
    t.index ["reconciliation_run_id"], name: "index_matches_on_reconciliation_run_id"
    t.index ["workspace_id"], name: "index_matches_on_workspace_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workspace_id", null: false
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_memberships_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_memberships_on_workspace_id"
  end

  create_table "reconcilable_items", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.string "amount_currency", default: "USD", null: false
    t.datetime "created_at", null: false
    t.bigint "data_source_id", null: false
    t.text "description", default: "", null: false
    t.datetime "discarded_at"
    t.string "external_id"
    t.string "external_id_hash", null: false
    t.bigint "import_batch_id", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.date "occurred_on", null: false
    t.string "status", default: "unmatched", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["data_source_id", "external_id_hash"], name: "idx_on_data_source_id_external_id_hash_d76a0e762a", unique: true
    t.index ["data_source_id"], name: "index_reconcilable_items_on_data_source_id"
    t.index ["discarded_at"], name: "index_reconcilable_items_on_discarded_at"
    t.index ["import_batch_id"], name: "index_reconcilable_items_on_import_batch_id"
    t.index ["item_type", "item_id"], name: "index_reconcilable_items_on_item"
    t.index ["workspace_id", "amount_cents"], name: "index_reconcilable_items_on_workspace_id_and_amount_cents"
    t.index ["workspace_id", "occurred_on"], name: "index_reconcilable_items_on_workspace_id_and_occurred_on"
    t.index ["workspace_id"], name: "index_reconcilable_items_on_workspace_id"
  end

  create_table "reconciliation_exceptions", force: :cascade do |t|
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.text "llm_explanation"
    t.bigint "reconcilable_item_id", null: false
    t.bigint "reconciliation_run_id", null: false
    t.string "resolution"
    t.datetime "resolved_at"
    t.bigint "resolved_by_user_id"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["reconcilable_item_id"], name: "index_reconciliation_exceptions_on_reconcilable_item_id"
    t.index ["reconciliation_run_id", "reconcilable_item_id"], name: "idx_unique_reconciliation_exception_per_run_item", unique: true
    t.index ["reconciliation_run_id"], name: "index_reconciliation_exceptions_on_reconciliation_run_id"
    t.index ["resolved_by_user_id"], name: "index_reconciliation_exceptions_on_resolved_by_user_id"
    t.index ["workspace_id"], name: "index_reconciliation_exceptions_on_workspace_id"
  end

  create_table "reconciliation_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.date "date_range_end", null: false
    t.date "date_range_start", null: false
    t.text "error_message"
    t.bigint "source_a_id", null: false
    t.bigint "source_b_id", null: false
    t.datetime "started_at"
    t.jsonb "stats", default: {}, null: false
    t.string "status", default: "queued", null: false
    t.bigint "triggered_by_user_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["source_a_id"], name: "index_reconciliation_runs_on_source_a_id"
    t.index ["source_b_id"], name: "index_reconciliation_runs_on_source_b_id"
    t.index ["triggered_by_user_id"], name: "index_reconciliation_runs_on_triggered_by_user_id"
    t.index ["workspace_id"], name: "index_reconciliation_runs_on_workspace_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "base_currency", default: "USD", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_events", "users"
  add_foreign_key "audit_events", "workspaces"
  add_foreign_key "bank_transactions", "workspaces"
  add_foreign_key "data_sources", "workspaces"
  add_foreign_key "import_batches", "data_sources"
  add_foreign_key "import_batches", "users"
  add_foreign_key "invoices", "workspaces"
  add_foreign_key "match_legs", "matches"
  add_foreign_key "match_legs", "reconcilable_items"
  add_foreign_key "matches", "reconciliation_runs"
  add_foreign_key "matches", "users", column: "confirmed_by_user_id"
  add_foreign_key "matches", "workspaces"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "reconcilable_items", "data_sources"
  add_foreign_key "reconcilable_items", "import_batches"
  add_foreign_key "reconcilable_items", "workspaces"
  add_foreign_key "reconciliation_exceptions", "reconcilable_items"
  add_foreign_key "reconciliation_exceptions", "reconciliation_runs"
  add_foreign_key "reconciliation_exceptions", "users", column: "resolved_by_user_id"
  add_foreign_key "reconciliation_exceptions", "workspaces"
  add_foreign_key "reconciliation_runs", "data_sources", column: "source_a_id"
  add_foreign_key "reconciliation_runs", "data_sources", column: "source_b_id"
  add_foreign_key "reconciliation_runs", "users", column: "triggered_by_user_id"
  add_foreign_key "reconciliation_runs", "workspaces"
end
