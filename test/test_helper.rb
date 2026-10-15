ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "rack/test"
require_relative "../simulator/app"

class ActiveSupport::TestCase
  parallelize(workers: 1)

  def product
    Product.create!(sku: "DEMO-001", name: "Workshop notebook", currency: "ZAR", price: "45.00")
  end
end

class ActionDispatch::IntegrationTest
  def operator_headers
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("operator", ENV.fetch("OPERATOR_PASSWORD")) }
  end
end

# Actual local TCP HTTP server; no inline request adapter replaces the provider boundary.
require "puma"
TEST_SUPPLIER = Puma::Server.new(SupplierSimulator.new(path: Rails.root.join("tmp/test-supplier.json")))
TEST_SUPPLIER.add_tcp_listener("127.0.0.1", 0)
ENV["SUPPLIER_PORT"] = TEST_SUPPLIER.connected_ports.first.to_s
TEST_SUPPLIER.run
at_exit { TEST_SUPPLIER.stop(true) }

class HttpSupplierTest < ActiveSupport::TestCase
  setup { SupplierClient.new.request("POST", "/reset", {}) }
end
