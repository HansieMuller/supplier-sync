require "openssl"

module WebhookSignature
  def self.sign(raw, timestamp)
    OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("WEBHOOK_SECRET"), "#{timestamp}.#{raw}")
  end

  def self.valid?(raw, timestamp, signature, now: Time.current)
    return false unless timestamp.to_s.match?(/\A[0-9]{10,12}\z/) && signature.to_s.match?(/\A[0-9a-f]{64}\z/)
    return false if (now.to_i - timestamp.to_i).abs > 300
    ActiveSupport::SecurityUtils.secure_compare(sign(raw, timestamp), signature)
  end
end
