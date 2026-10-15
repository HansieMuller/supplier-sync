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

ActiveRecord::Schema[8.1].define(version: 2026_10_15_000200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "attempts", force: :cascade do |t|
    t.bigint "operation_id", null: false
    t.integer "number", null: false
    t.string "outcome", default: "running", null: false
    t.string "code"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.index ["operation_id", "number"], name: "index_attempts_on_operation_id_and_number", unique: true
    t.index ["operation_id"], name: "index_attempts_on_operation_id"
  end

  create_table "catalogue_syncs", force: :cascade do |t|
    t.string "cursor"
    t.jsonb "seen_cursors", default: [], null: false
    t.string "state", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "operations", force: :cascade do |t|
    t.bigint "purchase_order_id"
    t.bigint "catalogue_sync_id"
    t.string "kind", null: false
    t.string "state", default: "pending", null: false
    t.integer "attempt_count", default: 0, null: false
    t.integer "cycle_attempts", default: 0, null: false
    t.integer "operator_retries", default: 0, null: false
    t.datetime "next_attempt_at", null: false
    t.string "delivery_token"
    t.string "claim_token"
    t.datetime "lease_expires_at"
    t.datetime "enqueued_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["catalogue_sync_id"], name: "index_operations_on_catalogue_sync_id", unique: true
    t.index ["purchase_order_id"], name: "index_operations_on_purchase_order_id", unique: true
    t.index ["state", "lease_expires_at"], name: "index_operations_on_state_and_lease_expires_at"
    t.index ["state", "next_attempt_at"], name: "index_operations_on_state_and_next_attempt_at"
    t.check_constraint "attempt_count >= 0 AND cycle_attempts >= 0 AND cycle_attempts <= 5 AND operator_retries >= 0 AND operator_retries <= 3", name: "bounded_attempt_budget"
    t.check_constraint "kind::text = 'submit_order'::text AND purchase_order_id IS NOT NULL AND catalogue_sync_id IS NULL OR kind::text = 'catalogue_sync'::text AND catalogue_sync_id IS NOT NULL AND purchase_order_id IS NULL", name: "operation_subject"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'queued'::character varying, 'running'::character varying, 'retry_wait'::character varying, 'completed'::character varying, 'failed'::character varying, 'manual_review'::character varying]::text[])", name: "valid_operation_state"
  end

  create_table "products", force: :cascade do |t|
    t.string "sku", null: false
    t.string "name", null: false
    t.string "currency", null: false
    t.decimal "price", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sku"], name: "index_products_on_sku", unique: true
    t.check_constraint "price >= 0::numeric AND (currency::text = ANY (ARRAY['ZAR'::character varying, 'USD'::character varying, 'EUR'::character varying]::text[]))", name: "valid_product_price"
  end

  create_table "purchase_orders", force: :cascade do |t|
    t.string "idempotency_key", null: false
    t.jsonb "payload", null: false
    t.string "state", default: "pending", null: false
    t.string "supplier_reference"
    t.integer "supplier_version", default: 0, null: false
    t.string "currency", null: false
    t.decimal "total", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_purchase_orders_on_idempotency_key", unique: true
    t.index ["supplier_reference"], name: "index_purchase_orders_on_supplier_reference", unique: true
    t.check_constraint "(state::text = ANY (ARRAY['pending'::character varying, 'accepted'::character varying, 'shipped'::character varying, 'delivered'::character varying, 'failed'::character varying, 'manual_review'::character varying]::text[])) AND supplier_version >= 0", name: "valid_order_state"
    t.check_constraint "total >= 0::numeric AND (currency::text = ANY (ARRAY['ZAR'::character varying, 'USD'::character varying, 'EUR'::character varying]::text[]))", name: "valid_order_total"
  end

  add_foreign_key "attempts", "operations"
  add_foreign_key "operations", "catalogue_syncs"
  add_foreign_key "operations", "purchase_orders"
end
