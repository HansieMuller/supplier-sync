require "test_helper"

class OperationReviewTest < ActionDispatch::IntegrationTest
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
end
