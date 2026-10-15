class OperationJob
  include Sidekiq::Job
  sidekiq_options queue: "supplier", retry: false

  # The database is the sole retry-budget owner; duplicate/stale deliveries are no-ops.
  def perform(id, delivery)
    operation = Operation.find_by(id: id)
    return unless operation
    token = operation.claim!(delivery)
    return unless token
    client = SupplierClient.new
    case operation.kind
    when "submit_order"
      order = operation.purchase_order
      result = client.lookup(order.idempotency_key) || client.submit(order.idempotency_key, order.payload)
      client.validate_order!(result, order.payload)
      operation.finish!(token, result: result)
    when "webhook"
      operation.finish!(token)
    when "catalogue_sync"
      guard = -> { operation.reload.lock!; operation.ensure_claim!(token) }
      operation.catalogue_sync.run!(client: client, guard: guard)
      operation.finish!(token)
    end
  rescue Operation::LostClaim
    # A replacement owns this operation; this process must not commit its result.
    nil
  rescue SupplierClient::Transient, SupplierClient::Permanent => e
    finish_error(operation, token, e)
  rescue StandardError => e
    Rails.logger.error("operation_failure id=#{id} error_class=#{e.class.name}")
    finish_error(operation, token, SupplierClient::Permanent.new("unexpected_error"))
  end

  private

  def finish_error(operation, token, error)
    operation.finish!(token, error: error) if token
  rescue Operation::LostClaim
    nil
  end
end
