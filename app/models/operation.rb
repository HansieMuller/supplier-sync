class Operation < ApplicationRecord
  class CapacityExceeded < StandardError; end
  class LostClaim < StandardError; end
  MAX_ATTEMPTS = 5
  LEASE = 60.seconds
  ACTIVE_STATES = %w[pending queued running retry_wait].freeze
  belongs_to :purchase_order, optional: true
  belongs_to :catalogue_sync, optional: true
  has_many :attempts, dependent: :restrict_with_exception
  scope :active, -> { where(state: ACTIVE_STATES) }
  scope :due, ->(now) { where(state: %w[pending retry_wait]).where("next_attempt_at <= ?", now) }

  # This row is the outbox intent. The caller's business transaction owns its commit.
  def self.admit!(attributes)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(8142201)")
      raise CapacityExceeded, "Work capacity reached; try later" if active.count >= 200
      create!(attributes.merge(next_attempt_at: Time.current))
    end
  end

  def claim!(delivery, now: Time.current)
    with_lock do
      return unless state == "queued" && delivery_token == delivery
      token = SecureRandom.uuid
      update!(state: "running", claim_token: token, lease_expires_at: now + LEASE,
        attempt_count: attempt_count + 1, cycle_attempts: cycle_attempts + 1)
      attempts.create!(number: attempt_count, started_at: now)
      token
    end
  end

  def ensure_claim!(token)
    raise LostClaim unless state == "running" && claim_token == token
  end

  # Fencing keeps an expired process from committing after a replacement claim.
  def finish!(token, result: nil, error: nil, now: Time.current, random: Random)
    with_lock do
      ensure_claim!(token)
      if error
        transient = error.is_a?(SupplierClient::Transient)
        terminal = !transient || cycle_attempts >= MAX_ATTEMPTS
        outcome = terminal ? (kind == "submit_order" && (transient || error.message != "http_422") ? "manual_review" : "failed") : "retry_wait"
        delay = [2**cycle_attempts + random.rand(0.0..1.0), error.respond_to?(:retry_after) ? error.retry_after.to_f : 0].max
        update!(state: outcome, last_error: error.message.to_s.first(100), next_attempt_at: now + delay, lease_expires_at: nil, claim_token: nil)
        purchase_order&.update!(state: outcome) if %w[failed manual_review].include?(outcome) && purchase_order && purchase_order.supplier_reference.nil?
        attempts.find_by!(number: attempt_count).update!(outcome: outcome, code: last_error, finished_at: now)
      else
        if kind == "submit_order"
          purchase_order.with_lock do
            if result.fetch("version") > purchase_order.supplier_version
              purchase_order.update!(state: result.fetch("status"), supplier_reference: result.fetch("reference"), supplier_version: result.fetch("version"))
            end
          end
        end
        update!(state: "completed", last_error: nil, lease_expires_at: nil, claim_token: nil)
        attempts.find_by!(number: attempt_count).update!(outcome: "completed", finished_at: now)
      end
    end
  end

  def self.recover_stale!(now: Time.current)
    where(state: %w[queued running]).where("lease_expires_at <= ?", now).find_each do |operation|
      operation.with_lock do
        next unless %w[queued running].include?(operation.state) && operation.lease_expires_at <= now
        if operation.state == "running"
          operation.finish!(operation.claim_token, error: SupplierClient::Transient.new("abandoned_claim"), now: now)
        else
          operation.update!(state: "retry_wait", next_attempt_at: now, delivery_token: nil, lease_expires_at: nil, last_error: "delivery_unconfirmed")
        end
      end
    end
  end

  # An operator grants a fresh bounded budget, keeping the immutable order/key and full attempt history.
  def retry_by_operator!
    with_lock do
      raise ArgumentError, "Only failed/manual-review operations can retry" unless %w[failed manual_review].include?(state)
      raise ArgumentError, "Operator retry limit reached" if operator_retries >= 3
      self.class.connection.execute("SELECT pg_advisory_xact_lock(8142201)")
      raise CapacityExceeded, "Work capacity reached" if self.class.active.count >= 200
      update!(state: "retry_wait", cycle_attempts: 0, operator_retries: operator_retries + 1, next_attempt_at: Time.current, last_error: nil)
      purchase_order&.update!(state: "pending") if purchase_order&.supplier_reference.nil?
    end
  end
end
