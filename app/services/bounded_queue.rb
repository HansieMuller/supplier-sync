require "sidekiq"

# Application producers use one atomic Redis admission check, including replacement deliveries.
# Only Sidekiq's open JSON job protocol is used; PostgreSQL remains the completion authority.
class BoundedQueue
  SCRIPT = <<~LUA.freeze
    if redis.call('LLEN', KEYS[1]) >= 100 then return 0 end
    redis.call('SADD', KEYS[2], 'supplier')
    redis.call('LPUSH', KEYS[1], ARGV[1])
    return 1
  LUA

  def self.push(id, delivery, jid: SecureRandom.hex(12))
    now = (Time.now.to_f * 1000).to_i
    payload = Sidekiq.dump_json("class" => "OperationJob", "args" => [id, delivery], "queue" => "supplier",
      "retry" => false, "jid" => jid, "created_at" => now, "enqueued_at" => now)
    Sidekiq.redis { |redis| redis.call("EVAL", SCRIPT, 2, "queue:supplier", "queues", payload) == 1 }
  end
end
