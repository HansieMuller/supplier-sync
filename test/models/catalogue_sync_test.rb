require "test_helper"

class CatalogueSyncTest < ActiveSupport::TestCase
  test "a terminal page 49 completes the sync and ordinary job" do
    assert_feed_outcome(49, "completed")
  end

  test "a terminal page 50 completes the sync and ordinary job" do
    assert_feed_outcome(50, "completed")
  end

  test "a feed requiring page 51 stops at the cap without claiming completion" do
    assert_feed_outcome(51, "failed")
  end

  private

  # A finite HTTP feed exercises the real client and the job's normal claim/finish path.
  def assert_feed_outcome(page_count, expected_state)
    requested_pages = []
    feed = lambda do |env|
      page = Rack::Request.new(env).params.fetch("cursor", "page-1").delete_prefix("page-").to_i
      requested_pages << page
      body = {
        items: [{ sku: "FEED-#{page}", name: "Fictional product #{page}", currency: "ZAR", price: "1.00" }],
        next_cursor: page < page_count ? "page-#{page + 1}" : nil
      }
      [200, { "content-type" => "application/json" }, [JSON.generate(body)]]
    end
    server = Puma::Server.new(feed)
    server.add_tcp_listener("127.0.0.1", 0)
    previous_port = ENV["SUPPLIER_PORT"]
    ENV["SUPPLIER_PORT"] = server.connected_ports.first.to_s
    server.run

    sync = CatalogueSync.schedule!
    operation = Operation.find_by!(catalogue_sync: sync)
    OperationJob.new.perform(*OutboxDispatcher.claim)

    assert_equal expected_state, operation.reload.state
    assert_equal expected_state == "completed" ? "completed" : "pending", sync.reload.state
    assert_equal (1..[page_count, 50].min).to_a, requested_pages
    assert_equal [page_count, 50].min, Product.count
    assert_equal 1, operation.attempt_count
    assert_equal expected_state, operation.attempts.sole.outcome
    if expected_state == "completed"
      assert_nil sync.cursor
      assert_nil operation.last_error
    else
      assert_equal "page-51", sync.cursor
      assert_equal "page_limit", operation.last_error
    end
  ensure
    server&.stop(true)
    ENV["SUPPLIER_PORT"] = previous_port
  end
end
