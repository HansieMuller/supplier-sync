require "sidekiq"
# A dedicated Redis database is required; do not share this queue with another app.
redis = { url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/12"), network_timeout: 1, pool_timeout: 1 }
Sidekiq.configure_client { |config| config.redis = redis }
Sidekiq.configure_server { |config| config.redis = redis }
