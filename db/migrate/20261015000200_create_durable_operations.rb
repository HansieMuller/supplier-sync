class CreateDurableOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :operations do |t|
      t.references :purchase_order, foreign_key: true, index: { unique: true }
      t.references :catalogue_sync, foreign_key: true, index: { unique: true }
      t.string :kind, null: false
      t.string :state, null: false, default: "pending"
      t.integer :attempt_count, null: false, default: 0
      t.integer :cycle_attempts, null: false, default: 0
      t.integer :operator_retries, null: false, default: 0
      t.datetime :next_attempt_at, null: false
      t.string :delivery_token
      t.string :claim_token
      t.datetime :lease_expires_at
      t.datetime :enqueued_at
      t.string :last_error
      t.timestamps
    end
    add_index :operations, [:state, :next_attempt_at]
    add_index :operations, [:state, :lease_expires_at]
    add_check_constraint :operations, "state IN ('pending','queued','running','retry_wait','completed','failed','manual_review')", name: "valid_operation_state"
    add_check_constraint :operations, "attempt_count >= 0 AND cycle_attempts BETWEEN 0 AND 5 AND operator_retries BETWEEN 0 AND 3", name: "bounded_attempt_budget"
    add_check_constraint :operations, "(kind = 'submit_order' AND purchase_order_id IS NOT NULL AND catalogue_sync_id IS NULL) OR (kind = 'catalogue_sync' AND catalogue_sync_id IS NOT NULL AND purchase_order_id IS NULL)", name: "operation_subject"
    create_table :attempts do |t|
      t.references :operation, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :outcome, null: false, default: "running"
      t.string :code
      t.datetime :started_at, null: false
      t.datetime :finished_at
    end
    add_index :attempts, [:operation_id, :number], unique: true
  end
end
