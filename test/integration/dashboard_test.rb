require "test_helper"
class DashboardTest < ActionDispatch::IntegrationTest
  test "operator authentication protects dashboard and writes" do
    get root_path
    assert_response :unauthorized
    post orders_path, params: { product_id: 1, quantity: 1 }
    assert_response :unauthorized
    get root_path, headers: operator_headers
    assert_response :success
    assert_includes response.body, "SupplierSync"
  end
  test "authenticated form requires CSRF and valid submission queues durable work" do
    selected_product = product
    ActionController::Base.allow_forgery_protection = true
    post orders_path, params: { product_id: selected_product.id, quantity: 1 }, headers: operator_headers
    assert_response :unprocessable_entity
    assert_equal 0, PurchaseOrder.count
    get root_path, headers: operator_headers
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    post orders_path, params: { product_id: selected_product.id, quantity: 1, authenticity_token: token }, headers: operator_headers
    assert_response :redirect
    operation = Operation.find_by!(purchase_order: PurchaseOrder.last)
    assert_equal "pending", operation.state
    get operation_path(operation), headers: operator_headers
    assert_response :success
    assert_includes response.body, "Attempt timeline"
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "authenticated statement upload and safe CSV export work over HTTP" do
    upload = Rack::Test::UploadedFile.new(Rails.root.join("demo/dirty-statement.csv"), "text/csv")
    post statements_path, params: { statement: upload }, headers: operator_headers
    assert_response :redirect
    statement = StatementImport.last
    assert_equal "completed", statement.state
    get statement_path(statement), headers: operator_headers
    assert_response :success
    assert_match "text/csv", response.media_type
    assert_includes response.body, "'=DEMO"
    assert_match "attachment", response.headers["Content-Disposition"]
    post statements_path, headers: operator_headers.merge("CONTENT_LENGTH" => "600001")
    assert_response :content_too_large
  end
end
