class CreateSupplierDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :sku, null: false
      t.string :name, null: false
      t.string :currency, null: false
      t.decimal :price, precision: 12, scale: 2, null: false
      t.timestamps
    end
    add_index :products, :sku, unique: true
    add_check_constraint :products, "price >= 0 AND currency IN ('ZAR', 'USD', 'EUR')", name: "valid_product_price"
    create_table :purchase_orders do |t|
      t.string :idempotency_key, null: false
      t.jsonb :payload, null: false
      t.string :state, null: false, default: "pending"
      t.string :supplier_reference
      t.integer :supplier_version, null: false, default: 0
      t.string :currency, null: false
      t.decimal :total, precision: 12, scale: 2, null: false
      t.timestamps
    end
    add_index :purchase_orders, :idempotency_key, unique: true
    add_index :purchase_orders, :supplier_reference, unique: true
    add_check_constraint :purchase_orders, "total >= 0 AND currency IN ('ZAR', 'USD', 'EUR')", name: "valid_order_total"
    add_check_constraint :purchase_orders, "state IN ('pending', 'accepted', 'shipped', 'delivered', 'failed', 'manual_review') AND supplier_version >= 0", name: "valid_order_state"
    create_table :catalogue_syncs do |t|
      t.string :cursor
      t.jsonb :seen_cursors, null: false, default: []
      t.string :state, null: false, default: "pending"
      t.timestamps
    end
  end
end
