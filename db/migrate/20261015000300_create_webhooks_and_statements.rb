class CreateWebhooksAndStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.string :event_key, null: false
      t.string :body_digest, null: false
      t.jsonb :payload, null: false
      t.string :state, null: false, default: "received"
      t.timestamps
    end
    add_index :webhook_events, :event_key, unique: true
    add_reference :operations, :webhook_event, foreign_key: true, index: { unique: true }
    remove_check_constraint :operations, "(kind = 'submit_order' AND purchase_order_id IS NOT NULL AND catalogue_sync_id IS NULL) OR (kind = 'catalogue_sync' AND catalogue_sync_id IS NOT NULL AND purchase_order_id IS NULL)", name: "operation_subject"
    add_check_constraint :operations, "(kind = 'submit_order' AND purchase_order_id IS NOT NULL AND catalogue_sync_id IS NULL AND webhook_event_id IS NULL) OR (kind = 'catalogue_sync' AND catalogue_sync_id IS NOT NULL AND purchase_order_id IS NULL AND webhook_event_id IS NULL) OR (kind = 'webhook' AND webhook_event_id IS NOT NULL AND purchase_order_id IS NULL AND catalogue_sync_id IS NULL)", name: "operation_subject"
    create_table :statement_imports do |t|
      t.string :digest, null: false
      t.string :filename, null: false
      t.string :state, null: false, default: "processing"
      t.string :error
      t.timestamps
    end
    add_index :statement_imports, :digest, unique: true
    create_table :statement_rows do |t|
      t.references :statement_import, null: false, foreign_key: true
      t.integer :line_number, null: false
      t.text :source, null: false
      t.jsonb :fields, null: false, default: {}
    end
    add_index :statement_rows, [:statement_import_id, :line_number], unique: true
    create_table :findings do |t|
      t.references :statement_row, null: false, foreign_key: true
      t.string :code, null: false
      t.string :detail, null: false
    end
    add_index :findings, [:statement_row_id, :code], unique: true
  end
end
