require "net/http"
require "json"
require "time"

class SupplierClient
  class Transient < StandardError
    attr_reader :retry_after
    def initialize(message, retry_after: nil)
      @retry_after = retry_after
      super(message)
    end
  end
  class Permanent < StandardError; end

  def catalogue(cursor)
    request("GET", "/catalogue" + (cursor ? "?cursor=#{URI.encode_www_form_component(cursor)}" : ""))
  end

  def lookup(key)
    request("GET", "/orders/#{URI.encode_www_form_component(key)}", missing: true)
  end

  def submit(key, payload)
    result = request("POST", "/orders", payload, key: key)
    validate_order!(result, payload)
  end

  def validate_order!(result, payload)
    unless result.is_a?(Hash) && result["reference"].to_s.match?(/\ASUP-[0-9]{1,10}\z/) &&
        %w[accepted shipped delivered].include?(result["status"]) && result["version"].is_a?(Integer) && result["version"] > 0 && result["payload"] == payload
      raise Permanent, "supplier_contract_mismatch"
    end
    result
  end

  # The host is a literal loopback address. No redirects, environment proxy or user-supplied URLs.
  def request(method, path, body = nil, key: nil, missing: false)
    http = Net::HTTP.new("127.0.0.1", DemoConfig.port("SUPPLIER_PORT", 4567), nil)
    http.open_timeout = 0.5
    http.read_timeout = 0.25
    http.write_timeout = 0.5
    http.max_retries = 0
    req = Net::HTTPGenericRequest.new(method, !body.nil?, true, path)
    req["Authorization"] = "Bearer #{ENV.fetch('SUPPLIER_TOKEN')}"
    req["Content-Type"] = "application/json"
    req["Idempotency-Key"] = key if key
    req.body = JSON.generate(body) if body
    content = +""
    status = nil
    headers = nil
    http.request(req) do |response|
      status = response.code.to_i
      headers = response
      response.read_body do |chunk|
        content << chunk
        raise Permanent, "response_too_large" if content.bytesize > 65_536
      end
    end
    return nil if status == 404 && missing
    if status == 429 || status >= 500
      retry_after = parse_retry_after(headers["Retry-After"])
      raise Transient.new("http_#{status}", retry_after: retry_after)
    end
    raise Permanent, "http_#{status}" unless (200..299).cover?(status)
    JSON.parse(content)
  rescue JSON::ParserError
    raise Permanent, "invalid_json"
  rescue Timeout::Error, EOFError, IOError, SocketError, SystemCallError => e
    raise Transient, e.class.name
  end

  def parse_retry_after(value)
    return if value.nil?
    seconds = value.match?(/\A[0-9]+\z/) ? value.to_i : (Time.httpdate(value) - Time.current).ceil
    [[seconds, 0].max, 86_400].min
  rescue ArgumentError
    nil
  end
end
