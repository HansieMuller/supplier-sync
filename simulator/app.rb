require "json"
require "rack"
require "fileutils"
require "digest"
require "bigdecimal"
require_relative "../lib/demo_config"
DemoConfig.load!

# Fictional provider. Its persistent ledger is deliberately separate from Rails/PostgreSQL.
class SupplierSimulator
  PRODUCTS = [
    { sku: "DEMO-001", name: "Workshop notebook", currency: "ZAR", price: "45.00" },
    { sku: "DEMO-002", name: "Graphite pencil set", currency: "ZAR", price: "30.00" },
    { sku: "DEMO-003", name: "Canvas tool pouch", currency: "ZAR", price: "125.00" }
  ].freeze

  def initialize(path: File.expand_path("../tmp/supplier-#{ENV.fetch('RAILS_ENV', 'development')}.json", __dir__))
    raise ArgumentError, "Simulator is development/test only" unless %w[development test].include?(ENV.fetch("RAILS_ENV", "development"))
    @path = path
  end

  def ledger
    FileUtils.mkdir_p(File.dirname(@path))
    File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
      file.flock(File::LOCK_EX)
      raw = file.read
      data = raw.empty? ? { "orders" => {}, "calls" => {}, "payloads" => {} } : JSON.parse(raw)
      result = yield data
      file.rewind
      file.write(JSON.generate(data))
      file.truncate(file.pos)
      file.flush
      file.fsync
      result
    end
  end

  def call(env)
    request = Rack::Request.new(env)
    return response(401, error: "unauthorized") unless Rack::Utils.secure_compare(request.get_header("HTTP_AUTHORIZATION").to_s, "Bearer #{ENV.fetch('SUPPLIER_TOKEN')}")
    case [request.request_method, request.path_info]
    when ["GET", "/health"] then response(200, status: "ok")
    when ["GET", "/catalogue"]
      cursor = request.params["cursor"]
      return response(422, error: "invalid_cursor") unless [nil, "page-2"].include?(cursor)
      response(200, items: cursor ? PRODUCTS.last(1) : PRODUCTS.first(2), next_cursor: cursor ? nil : "page-2")
    when ["POST", "/orders"]
      raw = request.body.read(16_385)
      return response(413, error: "too_large") if raw.bytesize > 16_384
      payload = JSON.parse(raw)
      return response(422, error: "invalid_order") unless payload.is_a?(Hash)
      key = request.get_header("HTTP_IDEMPOTENCY_KEY").to_s
      return response(422, error: "invalid_key") unless key.match?(/\A[0-9a-f-]{36}\z/)
      delay = false
      result = ledger do |data|
        data["payloads"] ||= {}
        if data["payloads"].key?(key) && data["payloads"][key] != payload
          next response(409, error: "key_payload_conflict")
        end
        data["payloads"][key] = payload
        existing = data["orders"][key]
        if existing
          next(existing["payload"] == payload ? response(200, existing) : response(409, error: "key_payload_conflict"))
        end
        calls = data["calls"][key] = data["calls"].fetch(key, 0) + 1
        scenario = payload["scenario"]
        next response(422, error: "validation") if scenario == "validation"
        next response(503, error: "unavailable") if scenario == "transient"
        next response(429, { error: "rate_limit" }, { "retry-after" => "2" }) if scenario == "rate_limit" && calls == 1
        item = PRODUCTS.find { |product| product[:sku] == payload["sku"] }
        unless item && payload["quantity"].is_a?(Integer) && (1..100).cover?(payload["quantity"]) && payload["currency"] == item[:currency] && payload["total"].is_a?(String) && payload["total"].match?(/\A[0-9]{1,10}\.[0-9]{1,2}\z/) && BigDecimal(payload["total"]) == BigDecimal(item[:price]) * payload["quantity"]
          next response(422, error: "invalid_order")
        end
        reference = "SUP-#{data['orders'].size + 1}"
        order = { "reference" => reference, "status" => "accepted", "version" => 1, "payload" => payload }
        data["orders"][key] = order
        delay = scenario == "accept_timeout"
        response(201, order)
      end
      # Intentional fault: durable acceptance precedes a delay longer than the client's read timeout.
      sleep 0.7 if delay
      result
    when ["POST", "/reset"]
      ledger { |data| data.replace({ "orders" => {}, "calls" => {}, "payloads" => {} }) }
      response(200, status: "reset")
    when ["GET", "/stats"]
      ledger { |data| response(200, order_count: data["orders"].size, calls: data["calls"]) }
    else
      if request.get? && request.path_info.start_with?("/orders/")
        key = request.path_info.delete_prefix("/orders/")
        ledger { |data| data["orders"][key] ? response(200, data["orders"][key]) : response(404, error: "unknown") }
      else
        response(404, error: "unknown")
      end
    end
  rescue JSON::ParserError, KeyError
    response(422, error: "malformed_json")
  rescue Timeout::Error, SystemCallError
    response(503, error: "receiver_unavailable")
  end

  def response(status, body = {}, headers = {})
    [status, { "content-type" => "application/json" }.merge(headers), [JSON.generate(body)]]
  end
end
