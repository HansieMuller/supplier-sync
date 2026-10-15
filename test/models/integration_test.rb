require "test_helper"

class SupplierIntegrationTest < HttpSupplierTest
  test "catalogue pages and stable order lookup use actual HTTP" do
    sync = CatalogueSync.create!
    sync.run!
    assert_equal "completed", sync.reload.state
    assert_equal 3, Product.count
    order = PurchaseOrder.place!(product: Product.first, quantity: 2)
    order.submit!
    reference = order.supplier_reference
    order.submit!
    assert_equal reference, order.reload.supplier_reference
    assert_equal 1, SupplierClient.new.request("GET", "/stats")["order_count"]
    assert_equal "90.0", order.payload["total"]
  end

  test "same key with different payload is rejected by the supplier" do
    order = PurchaseOrder.place!(product: product, quantity: 1)
    order.submit!
    error = assert_raises(SupplierClient::Permanent) { SupplierClient.new.submit(order.idempotency_key, order.payload.merge("quantity" => 2)) }
    assert_equal "http_409", error.message
  end

  test "page checkpoint survives interruption and rejects repeated cursor" do
    first_page = { "items" => [{ "sku" => "DEMO-001", "name" => "Notebook", "price" => "45.00", "currency" => "ZAR" }], "next_cursor" => "page-2" }
    client = Object.new
    client.define_singleton_method(:catalogue) { |cursor| cursor ? raise(SupplierClient::Transient, "interrupted") : first_page }
    sync = CatalogueSync.create!
    assert_raises(SupplierClient::Transient) { sync.run!(client: client) }
    assert_equal "page-2", sync.reload.cursor
    assert_equal 1, Product.count
    sync.run!
    assert_equal 2, Product.count
    assert_equal "completed", sync.reload.state
    sync = CatalogueSync.create!
    client.define_singleton_method(:catalogue) { |_| first_page }
    assert_raises(SupplierClient::Permanent) { sync.run!(client: client) }
    assert_equal "page-2", sync.reload.cursor
    client.define_singleton_method(:catalogue) { |_| first_page.merge("next_cursor" => "https://bad.example") }
    assert_raises(SupplierClient::Permanent) { sync.run!(client: client) }
  end

  test "validation errors remain permanent" do
    order = PurchaseOrder.place!(product: product, quantity: 1, scenario: "validation")
    assert_raises(SupplierClient::Permanent) { order.submit! }
    assert_equal 0, SupplierClient.new.request("GET", "/stats")["order_count"]
  end
end
