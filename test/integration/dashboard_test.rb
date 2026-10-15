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
end
