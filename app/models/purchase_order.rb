class PurchaseOrder < ApplicationRecord
  attr_readonly :idempotency_key, :payload, :total, :currency
  validates :idempotency_key, presence: true, uniqueness: true
  validates :state, inclusion: { in: %w[pending accepted shipped delivered failed manual_review] }

  # Snapshot catalogue prices so later syncs cannot change an already submitted order.
  def self.place!(product:, quantity:, scenario: "normal")
    raise ArgumentError, "Quantity must be between 1 and 100" unless quantity.to_s.match?(/\A[1-9][0-9]?\z|\A100\z/)
    raise ArgumentError, "Unknown scenario" unless %w[normal accept_timeout transient rate_limit validation].include?(scenario)
    raise ArgumentError, "Fault controls disabled" if Rails.env.production? && scenario != "normal"
    total = product.price * quantity.to_i
    create!(idempotency_key: SecureRandom.uuid, currency: product.currency, total: total,
      payload: { sku: product.sku, quantity: quantity.to_i, currency: product.currency, total: total.to_s("F"), scenario: scenario })
  end

  def submit!
    result = SupplierClient.new.lookup(idempotency_key) || SupplierClient.new.submit(idempotency_key, payload)
    SupplierClient.new.validate_order!(result, payload)
    update!(state: result.fetch("status"), supplier_reference: result.fetch("reference"), supplier_version: result.fetch("version"))
  end
end
