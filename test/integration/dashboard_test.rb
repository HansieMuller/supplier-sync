require "test_helper"
class DashboardTest < ActionDispatch::IntegrationTest
  test "dashboard identifies this educational project" do
    get root_path
    assert_response :success
    assert_includes response.body, "SupplierSync"
  end
end
