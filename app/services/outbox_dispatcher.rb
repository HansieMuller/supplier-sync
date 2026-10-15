class OutboxDispatcher
  def self.claim(now: Time.current)
    Operation.transaction do
      # Serializes admission counts across dispatchers, then row claims use SKIP LOCKED.
      Operation.connection.execute("SELECT pg_advisory_xact_lock(8142202)")
      return if Operation.where(state: %w[queued running]).count >= 50
      operation = Operation.due(now).order(:id).lock("FOR UPDATE SKIP LOCKED").first
      return unless operation
      operation.update!(state: "queued", delivery_token: SecureRandom.uuid, lease_expires_at: now + Operation::LEASE, enqueued_at: nil)
      [operation.id, operation.delivery_token]
    end
  end

  # No completion is inferred from Redis accepting a job. A crash on either side of
  # this enqueue is recovered from the queued row's expiring lease.
  def self.tick(now: Time.current, enqueue: BoundedQueue.method(:push))
    Operation.recover_stale!(now: now)
    20.times do
      claim = self.claim(now: now)
      break unless claim
      id, delivery = claim
      break unless enqueue.call(id, delivery)
      Operation.where(id: id, state: "queued", delivery_token: delivery).update_all(enqueued_at: now)
    end
  end
end
