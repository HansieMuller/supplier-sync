require "test_helper"

class WebhooksTest < ActionDispatch::IntegrationTest
  def event_body(id: "evt-1", reference: "SUP-1", version: 2, status: "shipped")
    JSON.generate(id: id, reference: reference, version: version, status: status)
  end

  def signed_post(body, timestamp: Time.current.to_i.to_s, signature: nil)
    post "/webhooks/supplier", params: body, headers: {
      "CONTENT_TYPE" => "application/json", "X-Supplier-Timestamp" => timestamp,
      "X-Supplier-Signature" => signature || WebhookSignature.sign(body, timestamp)
    }
  end

  def run_event(event)
    operation = event.operation
    delivery = SecureRandom.uuid
    operation.update!(state: "queued", delivery_token: delivery, lease_expires_at: 1.minute.from_now)
    OperationJob.new.perform(operation.id, delivery)
    operation.reload
  end

  test "raw-body signature tampering, stale/future timestamps and malformed JSON are rejected" do
    raw = event_body
    signed_post(raw + " ", signature: WebhookSignature.sign(raw, Time.current.to_i.to_s))
    assert_response :unauthorized
    signed_post(raw, timestamp: 301.seconds.ago.to_i.to_s)
    assert_response :unauthorized
    signed_post(raw, timestamp: 301.seconds.from_now.to_i.to_s)
    assert_response :unauthorized
    signed_post("{malformed")
    assert_response :unprocessable_entity
    signed_post(JSON.generate([]))
    assert_response :unprocessable_entity
    assert_equal 0, WebhookEvent.count
    signed_post(raw, signature: "x")
    assert_response :unauthorized
  end

  test "wrong field types, invalid encoding and unknown fields cannot reach PostgreSQL" do
    [true, false, 123, nil].each do |id|
      signed_post(JSON.generate(id: id, reference: "SUP-1", status: "shipped", version: 2))
      assert_response :unprocessable_entity
    end
    signed_post(event_body.sub("evt-1", "evt-\xFF".b))
    assert_response :bad_request # Rack rejects invalid UTF-8 before controller dispatch.
    assert_raises(WebhookEvent::Invalid) { WebhookEvent.accept!(event_body.sub("evt-1", "evt-\xFF".b)) }
    signed_post(JSON.generate(JSON.parse(event_body).merge("extra" => "\u0000")))
    assert_response :unprocessable_entity
    assert_equal 0, WebhookEvent.count
  end

  test "acceptance persists event and intent before acknowledgement and duplicate ids cannot change payload" do
    raw = event_body
    assert_difference ["WebhookEvent.count", "Operation.count"], 1 do
      signed_post(raw)
      assert_response :accepted
    end
    assert_no_difference ["WebhookEvent.count", "Operation.count"] do
      signed_post(raw)
      assert_response :accepted
    end
    signed_post(event_body(version: 3))
    assert_response :conflict
    assert_equal 2, WebhookEvent.first.payload["version"]
    signed_post(raw, timestamp: 301.seconds.ago.to_i.to_s)
    assert_response :unauthorized
  end

  test "version rule ignores out-of-order updates and flags equal-version conflicts" do
    order = PurchaseOrder.create!(idempotency_key: SecureRandom.uuid, payload: {}, total: "45.00", currency: "ZAR", state: "accepted", supplier_reference: "SUP-1", supplier_version: 1)
    event = WebhookEvent.accept!(event_body(version: 3, status: "delivered"))
    assert_equal "completed", run_event(event).state
    old = WebhookEvent.accept!(event_body(id: "evt-old", version: 2, status: "shipped"))
    run_event(old)
    assert_equal "ignored_old", old.reload.state
    assert_equal "delivered", order.reload.state
    same = WebhookEvent.accept!(event_body(id: "evt-same", version: 3, status: "delivered"))
    assert_equal "completed", run_event(same).state
    assert_equal "ignored_duplicate_version", same.reload.state
    conflict = WebhookEvent.accept!(event_body(id: "evt-conflict", version: 3, status: "shipped"))
    assert_equal "manual_review", run_event(conflict).state
    assert_equal "delivered", order.reload.state
    unknown = WebhookEvent.accept!(event_body(id: "evt-unknown", reference: "SUP-999"))
    assert_equal "manual_review", run_event(unknown).state
  end

  test "webhook receipt rolls back when outbox admission fails" do
    200.times do
      Operation.create!(kind: "catalogue_sync", catalogue_sync: CatalogueSync.create!, next_attempt_at: Time.current)
    end
    assert_no_difference "WebhookEvent.count" do
      signed_post(event_body)
      assert_response :service_unavailable
    end
  end

  test "operator retries and CSV exports require authentication" do
    patch "/operations/1"
    assert_response :unauthorized
    get "/statements/1"
    assert_response :unauthorized
  end
end
