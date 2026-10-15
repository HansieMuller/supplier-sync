class WebhookEvent < ApplicationRecord
  class Conflict < StandardError; end
  class Invalid < StandardError; end
  has_one :operation

  def self.accept!(raw)
    payload = JSON.parse(raw)
    unless payload.is_a?(Hash) && payload["id"].to_s.match?(/\A[A-Za-z0-9-]{1,64}\z/) &&
        payload["reference"].to_s.match?(/\ASUP-[0-9]{1,10}\z/) && %w[accepted shipped delivered].include?(payload["status"]) &&
        payload["version"].is_a?(Integer) && payload["version"].between?(1, 2_147_483_647)
      raise Invalid, "invalid_event"
    end
    transaction do
      event = create_or_find_by!(event_key: payload.fetch("id")) do |record|
        record.payload = payload
        record.body_digest = Digest::SHA256.hexdigest(raw)
      end
      raise Conflict, "event_id_reused" unless event.body_digest == Digest::SHA256.hexdigest(raw)
      Operation.admit!(kind: "webhook", webhook_event: event) if event.previously_new_record?
      event
    end
  rescue JSON::ParserError
    raise Invalid, "malformed_json"
  end

  # Versions are authoritative: lower versions are ignored, equal versions must agree.
  # A statement import never invokes this path; only authenticated supplier events do.
  def apply!
    order = PurchaseOrder.find_by(supplier_reference: payload.fetch("reference"))
    raise SupplierClient::Permanent, "unknown_order" unless order
    order.with_lock do
      incoming = payload.fetch("version")
      if incoming < order.supplier_version
        update!(state: "ignored_old")
      elsif incoming == order.supplier_version
        raise SupplierClient::Permanent, "version_conflict" unless payload.fetch("status") == order.state
        update!(state: "ignored_duplicate_version")
      else
        order.update!(state: payload.fetch("status"), supplier_version: incoming)
        update!(state: "applied")
      end
    end
  end
end
