require "test_helper"

class OperationReviewTest < ActionDispatch::IntegrationTest
  setup { SupplierClient.new.request("POST", "/reset", {}) }

  test "attention navigation reaches an old exception and preserves the safe retry identity" do
    event = WebhookEvent.accept!(JSON.generate(id: "old-event", reference: "SUP-999", status: "shipped", version: 2))
    operation = event.operation
    OperationJob.new.perform(*OutboxDispatcher.claim)
    assert_equal "manual_review", operation.reload.state
    20.times do
      Operation.create!(kind: "catalogue_sync", catalogue_sync: CatalogueSync.create!, state: "failed", next_attempt_at: Time.current)
    end
    16.times do
      Operation.create!(kind: "catalogue_sync", catalogue_sync: CatalogueSync.create!, state: "completed", next_attempt_at: Time.current)
    end

    get root_path, headers: operator_headers
    assert_select 'a[href=?]', operation_path(operation), count: 0
    assert_select 'a[href=?]', operations_path, text: /Need attention/
    get operations_path, headers: operator_headers
    assert_response :success
    assert_select "tbody tr", count: 20
    assert_select "td", text: "Completed", count: 0
    older_link = Nokogiri::HTML(response.body).at_css('a[rel="next"]')
    assert older_link, "An older attention page is navigable"
    get older_link["href"], headers: operator_headers
    assert_select "tbody tr", count: 1
    assert_select 'a[href=?]', operation_path(operation), count: 1

    ActionController::Base.allow_forgery_protection = true
    get operation_path(operation), headers: operator_headers
    assert_response :success
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    assert_no_difference ["Operation.count", "WebhookEvent.count"] do
      patch operation_path(operation), params: { authenticity_token: token }, headers: operator_headers
      assert_response :redirect
    end
    assert_equal "retry_wait", operation.reload.state
    assert_equal 1, operation.operator_retries
    assert_equal event.id, operation.webhook_event_id
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "attention list requires authentication and explains an empty result" do
    get operations_path
    assert_response :unauthorized
    get operations_path, headers: operator_headers
    assert_response :success
    assert_select ".empty", text: "No operations need attention."
    assert_select 'a[rel="next"]', count: 0
    get operations_path(before: 1), headers: operator_headers
    assert_select ".empty", text: "No older operations need attention."
    ["bad", "0", "-1", "9223372036854775808"].each do |cursor|
      get operations_path(before: cursor), headers: operator_headers
      assert_response :bad_request
    end
  end

  test "unknown webhook context is read only and retries the original event after acceptance recovery" do
    travel_to Time.utc(2026, 10, 15, 12)
    order = PurchaseOrder.place!(product: product, quantity: 1, scenario: "accept_timeout")
    submission = order.operation
    OperationJob.new.perform(*OutboxDispatcher.claim)
    assert_equal "retry_wait", submission.reload.state
    assert_nil order.reload.supplier_reference

    raw = JSON.generate(id: "early-shipment", reference: "SUP-1", status: "shipped", version: 2)
    timestamp = Time.current.to_i.to_s
    post "/webhooks/supplier", params: raw, headers: {
      "CONTENT_TYPE" => "application/json", "X-Supplier-Timestamp" => timestamp,
      "X-Supplier-Signature" => WebhookSignature.sign(raw, timestamp)
    }
    assert_response :accepted
    event = WebhookEvent.find_by!(event_key: "early-shipment")
    review = event.operation
    OperationJob.new.perform(*OutboxDispatcher.claim)
    assert_equal "unknown_order", review.reload.last_error
    assert_equal "manual_review", review.state
    original_event = event.attributes.slice("id", "event_key", "payload", "body_digest", "created_at")

    get operation_path(review), headers: operator_headers
    assert_select "#webhook-context", text: /early-shipment/
    assert_select "#webhook-context", text: /SUP-1/
    assert_select "#webhook-context", text: /No local order currently matches/
    assert_select "#webhook-context input, #webhook-context textarea", count: 0

    OperationJob.new.perform(*OutboxDispatcher.claim(now: 1.day.from_now))
    assert_equal "completed", submission.reload.state
    assert_equal "SUP-1", order.reload.supplier_reference
    get operation_path(review), headers: operator_headers
    assert_select "#webhook-context", text: /Current supplier version.*1/m
    assert_select "#webhook-context", text: /Current order status.*Accepted/m
    assert_no_difference ["Operation.count", "WebhookEvent.count"] do
      patch operation_path(review), headers: operator_headers
      assert_response :redirect
      OperationJob.new.perform(*OutboxDispatcher.claim)
    end
    assert_equal "completed", review.reload.state
    assert_equal 1, review.operator_retries
    assert_equal %w[manual_review completed], review.attempts.order(:number).pluck(:outcome)
    assert_equal original_event, event.reload.attributes.slice(*original_event.keys)
    assert_equal "applied", event.state
    assert_equal "shipped", order.reload.state
    assert_equal 2, order.supplier_version
    get operation_path(review), headers: operator_headers
    assert_select "#webhook-context", text: /Processing result.*Applied/m
  end

  test "equal-version disagreement shows incoming and current context without changing the order" do
    order = PurchaseOrder.create!(idempotency_key: SecureRandom.uuid, payload: {}, total: "45.00", currency: "ZAR", state: "delivered", supplier_reference: "SUP-1", supplier_version: 3)
    event = WebhookEvent.accept!(JSON.generate(id: "conflicting-shipment", reference: "SUP-1", status: "shipped", version: 3))
    OperationJob.new.perform(*OutboxDispatcher.claim)
    operation = event.operation.reload
    assert_equal "manual_review", operation.state
    assert_equal "version_conflict", operation.last_error
    get operation_path(operation), headers: operator_headers
    assert_select "#webhook-context", text: /conflicting-shipment/
    assert_select "#webhook-context", text: /Incoming status.*Shipped/m
    assert_select "#webhook-context", text: /Incoming version.*3/m
    assert_select "#webhook-context", text: /Receipt state.*Persisted/m
    assert_select "#webhook-context", text: /Processing result.*Received/m
    assert_select "#webhook-context", text: /Current order status.*Delivered/m
    assert_select "#webhook-context", text: /Current supplier version.*3/m
    assert_equal "delivered", order.reload.state
    assert_equal 3, order.supplier_version
  end
end
