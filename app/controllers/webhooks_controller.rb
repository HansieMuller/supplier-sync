# This endpoint uses a signed raw-body contract instead of browser session authentication.
class WebhooksController < ActionController::Base
  skip_forgery_protection only: :create

  def create
    raw = request.body.read(32_769)
    return head :payload_too_large if raw.bytesize > 32_768
    return head :unauthorized unless WebhookSignature.valid?(raw, request.headers["X-Supplier-Timestamp"], request.headers["X-Supplier-Signature"])
    WebhookEvent.accept!(raw)
    head :accepted
  rescue WebhookEvent::Invalid
    head :unprocessable_entity
  rescue WebhookEvent::Conflict
    head :conflict
  rescue Operation::CapacityExceeded
    head :service_unavailable
  end
end
