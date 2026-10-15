require "securerandom"
require "json"
require "fileutils"

# Local secrets are generated once, never committed or printed in logs.
module DemoConfig
  def self.load!
    path = File.expand_path("../tmp/demo-secrets.json", __dir__)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
      file.flock(File::LOCK_EX)
      content = file.read
      if content.empty?
        content = JSON.generate(%w[OPERATOR_PASSWORD SUPPLIER_TOKEN WEBHOOK_SECRET].to_h { |key| [key, SecureRandom.hex(32)] })
        file.write(content)
        file.flush
      end
      JSON.parse(content).each { |key, value| ENV[key] ||= value }
    end
  end

  def self.port(key, default)
    value = Integer(ENV.fetch(key, default.to_s), 10)
    raise ArgumentError, "Invalid local port" unless (1024..65535).cover?(value)
    value
  end
end
