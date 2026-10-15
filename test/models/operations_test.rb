require "test_helper"

class OperationsTest < HttpSupplierTest
  def dispatch_and_run(operation)
    id, delivery = OutboxDispatcher.claim(now: 1.day.from_now)
    assert_equal operation.id, id
    OperationJob.new.perform(id, delivery)
    operation.reload
  end

  test "valid product prices and quantities cannot overflow the order decimal total" do
    selected_product = product
    selected_product.update!(price: "9999999999.99")
    assert_no_difference ["PurchaseOrder.count", "Operation.count"] do
      assert_raises(ArgumentError) { PurchaseOrder.place!(product: selected_product, quantity: 2) }
    end
  end

  test "business row and outbox intent rollback together" do
    assert_no_difference ["PurchaseOrder.count", "Operation.count"] do
      PurchaseOrder.transaction do
        PurchaseOrder.place!(product: product, quantity: 1)
        raise ActiveRecord::Rollback
      end
    end
  end

  test "acceptance followed by real HTTP timeout recovers by lookup without duplicate" do
    order = PurchaseOrder.place!(product: product, quantity: 1, scenario: "accept_timeout")
    operation = Operation.find_by!(purchase_order: order)
    dispatch_and_run(operation)
    assert_equal "retry_wait", operation.state
    assert_equal "Net::ReadTimeout", operation.last_error
    assert_equal "pending", order.reload.state
    dispatch_and_run(operation)
    assert_equal "completed", operation.state
    assert_equal "accepted", order.reload.state
    assert_equal 1, SupplierClient.new.request("GET", "/stats")["order_count"]
    assert_equal 1, SupplierClient.new.request("GET", "/stats")["calls"][order.idempotency_key]
    assert_equal %w[retry_wait completed], operation.attempts.order(:number).pluck(:outcome)
  end

  test "duplicate deliveries and expired process results cannot change completed work" do
    order = PurchaseOrder.place!(product: product, quantity: 1)
    operation = Operation.find_by!(purchase_order: order)
    id, delivery = OutboxDispatcher.claim
    OperationJob.new.perform(id, delivery)
    OperationJob.new.perform(id, delivery)
    assert_equal 1, operation.attempts.count
    assert_equal "completed", operation.reload.state
    assert_raises(Operation::LostClaim) { operation.finish!("expired", result: {}) }
  end

  test "running claims recover and late results are fenced" do
    order = PurchaseOrder.place!(product: product, quantity: 1)
    operation = Operation.find_by!(purchase_order: order)
    _, delivery = OutboxDispatcher.claim
    old_token = operation.claim!(delivery)
    Operation.recover_stale!(now: 2.minutes.from_now)
    assert_equal "retry_wait", operation.reload.state
    assert_equal "abandoned_claim", operation.last_error
    assert_raises(Operation::LostClaim) { operation.finish!(old_token, result: {}) }
    dispatch_and_run(operation)
    assert_equal "completed", operation.state
  end

  test "both enqueue crash windows preserve intent" do
    order = PurchaseOrder.place!(product: product, quantity: 1)
    operation = Operation.find_by!(purchase_order: order)
    assert_raises(IOError) { OutboxDispatcher.tick(enqueue: ->(*) { raise IOError, "before enqueue" }) }
    assert_equal "queued", operation.reload.state
    assert_nil operation.enqueued_at
    Operation.recover_stale!(now: 2.minutes.from_now)
    delivered = []
    assert_raises(IOError) do
      OutboxDispatcher.tick(now: 3.minutes.from_now, enqueue: ->(id, token) { delivered << [id, token]; raise IOError, "after enqueue" })
    end
    OperationJob.new.perform(*delivered.first)
    assert_equal "completed", operation.reload.state
    Operation.recover_stale!(now: 1.hour.from_now)
    assert_equal "completed", operation.reload.state
  end

  test "retry exhaustion and operator retries preserve identity" do
    order = PurchaseOrder.place!(product: product, quantity: 1, scenario: "transient")
    operation = Operation.find_by!(purchase_order: order)
    key = order.idempotency_key
    5.times { dispatch_and_run(operation) }
    assert_equal "manual_review", operation.state
    assert_equal 5, operation.attempts.count
    assert_nil OutboxDispatcher.claim(now: 1.day.from_now)
    operation.retry_by_operator!
    assert_equal key, order.reload.idempotency_key
    assert_equal 0, operation.cycle_attempts
    assert_equal 5, operation.attempt_count
    assert_equal 1, operation.operator_retries
  end

  test "429 schedules Retry-After and validation does not retry" do
    order = PurchaseOrder.place!(product: product, quantity: 1, scenario: "rate_limit")
    operation = Operation.find_by!(purchase_order: order)
    travel_to Time.utc(2026, 10, 15, 10) do
      operation.update!(next_attempt_at: Time.current)
      dispatch_and_run(operation)
      assert_equal "retry_wait", operation.state
      assert_operator operation.next_attempt_at, :>=, 2.seconds.from_now
      assert_operator operation.next_attempt_at, :<=, 3.seconds.from_now
      assert_nil OutboxDispatcher.claim
    end
    dispatch_and_run(operation)
    assert_equal "completed", operation.state
    order = PurchaseOrder.place!(product: Product.first, quantity: 1, scenario: "validation")
    operation = Operation.find_by!(purchase_order: order)
    dispatch_and_run(operation)
    assert_equal "failed", operation.state
    assert_equal 1, operation.attempts.count
  end

  test "operator retry budgets are bounded and replaced queued deliveries are ignored" do
    order = PurchaseOrder.place!(product: product, quantity: 1)
    operation = Operation.find_by!(purchase_order: order)
    id, old_delivery = OutboxDispatcher.claim
    Operation.recover_stale!(now: 2.minutes.from_now)
    _, new_delivery = OutboxDispatcher.claim(now: 3.minutes.from_now)
    OperationJob.new.perform(id, old_delivery)
    assert_equal 0, operation.attempts.count
    OperationJob.new.perform(id, new_delivery)
    assert_equal "completed", operation.reload.state
    operation.update!(state: "manual_review", operator_retries: 3)
    assert_raises(ArgumentError) { operation.retry_by_operator! }
    assert_equal 3, operation.reload.operator_retries
  end

  test "catalogue terminal failures and exhausted abandoned claims do not stall dispatch" do
    sync = CatalogueSync.schedule!
    operation = Operation.find_by!(catalogue_sync: sync)
    _, delivery = OutboxDispatcher.claim
    token = operation.claim!(delivery)
    operation.finish!(token, error: SupplierClient::Permanent.new("invalid_cursor"))
    assert_equal "failed", operation.reload.state
    operation.retry_by_operator!
    operation.update!(cycle_attempts: 4)
    _, delivery = OutboxDispatcher.claim
    operation.claim!(delivery)
    Operation.recover_stale!(now: 2.minutes.from_now)
    assert_equal "failed", operation.reload.state
    assert_equal "abandoned_claim", operation.last_error
    assert_nil OutboxDispatcher.claim(now: 1.day.from_now)
  end

  test "physical Redis queue admission stays bounded" do
    Sidekiq.redis { |redis| redis.call("DEL", "queue:supplier", "queues") }
    100.times { assert BoundedQueue.push(1, SecureRandom.uuid) }
    assert_not BoundedQueue.push(1, SecureRandom.uuid)
    assert_equal 100, Sidekiq.redis { |redis| redis.call("LLEN", "queue:supplier") }
  ensure
    Sidekiq.redis { |redis| redis.call("DEL", "queue:supplier", "queues") }
  end
end

class CompetingTransactionsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Attempt.delete_all
    Operation.delete_all
    WebhookEvent.delete_all
    Finding.delete_all
    StatementRow.delete_all
    StatementImport.delete_all
    PurchaseOrder.delete_all
    CatalogueSync.delete_all
    Product.delete_all
  end
  teardown do
    Attempt.delete_all
    Operation.delete_all
    WebhookEvent.delete_all
    Finding.delete_all
    StatementRow.delete_all
    StatementImport.delete_all
    PurchaseOrder.delete_all
    CatalogueSync.delete_all
    Product.delete_all
  end

  # A barrier releases two independent PostgreSQL sessions together, with no timing sleeps.
  def competing(&block)
    ready, release, results = Queue.new, Queue.new, Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          release.pop
          results << block.call
        end
      end
    end
    2.times { ready.pop }
    2.times { release << true }
    threads.each(&:value)
    2.times.map { results.pop }
  end

  test "competing dispatchers claim one durable intent once" do
    order = PurchaseOrder.place!(product: product, quantity: 1)
    results = competing { OutboxDispatcher.claim }
    assert_equal 1, results.compact.size
    operation = Operation.find_by!(purchase_order: order)
    delivery = results.compact.first.last
    tokens = competing { Operation.find(operation.id).claim!(delivery) }
    assert_equal 1, tokens.compact.size
    assert_equal 1, operation.attempts.count
  end

  test "catalogue admission coalesces simultaneous requests" do
    results = competing { CatalogueSync.schedule!.id }
    assert_equal 1, results.uniq.size
    assert_equal 1, Operation.count
  end

  test "active operation admission cannot exceed its boundary under a race" do
    199.times do
      Operation.create!(kind: "catalogue_sync", catalogue_sync: CatalogueSync.create!, next_attempt_at: Time.current)
    end
    selected_product = product
    results = competing do
      begin
        PurchaseOrder.place!(product: selected_product, quantity: 1).id
      rescue Operation::CapacityExceeded
        :full
      end
    end
    assert_equal 1, results.count(:full)
    assert_equal 200, Operation.active.count
    assert_equal 1, PurchaseOrder.count
  end

  test "outstanding claim admission cannot exceed its boundary under a race" do
    51.times do |index|
      Operation.create!(kind: "catalogue_sync", catalogue_sync: CatalogueSync.create!, next_attempt_at: Time.current,
        state: index < 49 ? "queued" : "pending", lease_expires_at: 1.minute.from_now)
    end
    assert_equal 1, competing { OutboxDispatcher.claim }.compact.size
    assert_equal 50, Operation.where(state: "queued").count
  end

  test "physical Redis capacity is atomic between producers" do
    Sidekiq.redis { |redis| redis.call("DEL", "queue:supplier", "queues") }
    99.times { BoundedQueue.push(1, SecureRandom.uuid) }
    assert_equal [false, true], competing { BoundedQueue.push(1, SecureRandom.uuid) }.sort_by { |value| value ? 1 : 0 }
    assert_equal 100, Sidekiq.redis { |redis| redis.call("LLEN", "queue:supplier") }
  ensure
    Sidekiq.redis { |redis| redis.call("DEL", "queue:supplier", "queues") }
  end

  test "competing identical webhook receipts produce one event and one intent" do
    raw = JSON.generate(id: "concurrent-event", reference: "SUP-1", status: "shipped", version: 2)
    ids = competing { WebhookEvent.accept!(raw).id }
    assert_equal 1, ids.uniq.size
    assert_equal 1, WebhookEvent.count
    assert_equal 1, Operation.count
  end

  test "concurrent webhook versions finish at the highest version" do
    order = PurchaseOrder.create!(idempotency_key: SecureRandom.uuid, payload: {}, total: "45.00", currency: "ZAR", state: "accepted", supplier_reference: "SUP-1", supplier_version: 1)
    events = Queue.new
    [2, 3].each do |version|
      events << WebhookEvent.accept!(JSON.generate(id: "version-#{version}", reference: "SUP-1", status: version == 2 ? "shipped" : "delivered", version: version)).id
    end
    competing do
      operation = WebhookEvent.find(events.pop).operation
      delivery = SecureRandom.uuid
      operation.update!(state: "queued", delivery_token: delivery, lease_expires_at: 1.minute.from_now)
      OperationJob.new.perform(operation.id, delivery)
    end
    assert_equal "delivered", order.reload.state
    assert_equal 3, order.supplier_version
    assert_equal ["completed"], Operation.distinct.pluck(:state)
  end

  test "competing identical statement imports preserve one set of provenance and findings" do
    text = "reference,status,currency,total\nSUP-999,accepted,ZAR,45.00\n"
    ids = competing { StatementImport.process!(StringIO.new(text)).id }
    assert_equal 1, ids.uniq.size
    assert_equal 1, StatementRow.count
    assert_equal 1, Finding.count
  end

  test "other sessions do not observe rolled-back business/outbox rows" do
    ready, release, observed = Queue.new, Queue.new, Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ready.pop
        observed << [PurchaseOrder.count, Operation.count]
        release << true
      end
    end
    PurchaseOrder.transaction do
      PurchaseOrder.place!(product: product, quantity: 1)
      ready << true
      release.pop
      raise ActiveRecord::Rollback
    end
    thread.value
    assert_equal [0, 0], observed.pop
    assert_equal 0, Operation.count
  end
end
