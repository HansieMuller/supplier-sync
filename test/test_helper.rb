ENV["RAILS_ENV"] ||= "test"
require_relative "../config/boot"
require "uri"
redis_uri = URI(ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/13"))
redis_uri.path = "/13"
ENV["REDIS_URL"] = redis_uri.to_s
require_relative "../config/environment"
require "rails/test_help"
require "rack/test"
require_relative "../simulator/app"

class ActiveSupport::TestCase
  parallelize(workers: 1)

  # db:prepare may legitimately seed catalogue intent on a fresh database.
  # Each suite owns an empty, explicitly named test DB; never clear development data.
  def self.clear_demo_records!
    unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == "supplier_sync_test"
      raise "Behavior tests require the isolated supplier_sync_test database"
    end
    ActiveRecord::Base.transaction do
      [Finding, StatementRow, StatementImport, Attempt, Operation, WebhookEvent, PurchaseOrder, CatalogueSync, Product].each(&:delete_all)
    end
  end

  def product
    Product.create!(sku: "DEMO-001", name: "Workshop notebook", currency: "ZAR", price: "45.00")
  end
end

ActiveSupport::TestCase.clear_demo_records!

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
