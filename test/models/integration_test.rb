require "test_helper"

class SupplierIntegrationTest < HttpSupplierTest
  def submit(order)
    client = SupplierClient.new
    result = client.lookup(order.idempotency_key) || client.submit(order.idempotency_key, order.payload)
    client.validate_order!(result, order.payload)
  end

  test "catalogue pages and stable order lookup use actual HTTP" do
    sync = CatalogueSync.create!
    sync.run!
    assert_equal "completed", sync.reload.state
    assert_equal 3, Product.count
    order = PurchaseOrder.place!(product: Product.first, quantity: 2)
    reference = submit(order).fetch("reference")
    assert_equal reference, submit(order).fetch("reference")
    assert_equal 1, SupplierClient.new.request("GET", "/stats")["order_count"]
    assert_equal "90.0", order.payload["total"]
  end

  test "same key with different payload is rejected by the supplier" do
    order = PurchaseOrder.place!(product: product, quantity: 1)
    submit(order)
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

  test "key payload identity is retained even after supplier rejection" do
    order = PurchaseOrder.place!(product: product, quantity: 1, scenario: "rate_limit")
    assert_raises(SupplierClient::Transient) { SupplierClient.new.submit(order.idempotency_key, order.payload) }
    error = assert_raises(SupplierClient::Permanent) { SupplierClient.new.submit(order.idempotency_key, order.payload.merge("scenario" => "normal")) }
    assert_equal "http_409", error.message
  end

  test "Retry-After supports dates and rejects excessive deferral instead of retrying early" do
    client = SupplierClient.new
    travel_to Time.utc(2026, 10, 15, 10) do
      assert_equal 120, client.parse_retry_after(2.minutes.from_now.httpdate)
      assert_equal 120, client.parse_retry_after("120")
      assert_equal 0, client.parse_retry_after(2.minutes.ago.httpdate)
      assert_nil client.parse_retry_after("bad")
      assert_nil client.parse_retry_after("-1")
      assert_raises(SupplierClient::Permanent) { client.parse_retry_after("86401") }
    end
  end

  test "validation errors remain permanent" do
    order = PurchaseOrder.place!(product: product, quantity: 1, scenario: "validation")
    assert_raises(SupplierClient::Permanent) { submit(order) }
    assert_equal 0, SupplierClient.new.request("GET", "/stats")["order_count"]
  end
end
