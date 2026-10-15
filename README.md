# SupplierSync

An **AI-assisted portfolio demonstration**, built with original project code and fictional fixtures. It establishes no production, customer, scale or employment claims.

Ruby 4.0.7, Rails 8.1.4 and PostgreSQL 17. Rails 8.1 receives security maintenance through October 2027; review dependency updates before any public deployment.

```sh
bundle install
bin/rails db:prepare
bin/rails server -b 127.0.0.1
bin/rails test
```

This baseline boots a server-rendered dashboard. The implementation branch adds the supplier simulator, durable operations, Sidekiq processing, signed webhooks and statement reconciliation. No paid services or external credentials are needed.

## Working integration (slice 1)

Start `bin/supplier` in a second terminal before `bin/rails db:seed`. Use `bin/demo-password` to display your generated, untracked local operator password; username is `operator`. `bin/rails demo:reset` resets fictional data (stop background processes first). `bin/rails test` runs a real local HTTP simulator on an ephemeral loopback port.

Optional local PostgreSQL/Redis: `docker compose up -d`, then export `PGPORT=55432 PGUSER=supplier_sync REDIS_URL=redis://127.0.0.1:56379/0`. Compose trust authentication is restricted to local demonstration use.

## Queues and recovery (slice 2)

Run Redis, `bundle exec sidekiq -C config/sidekiq.yml`, and `bin/dispatch` alongside Rails and the simulator. The dispatcher polls PostgreSQL; jobs never sleep for backoff. The operation row is the transactional outbox intent and completion record. A 60-second lease recovers queued-but-lost deliveries and abandoned work. Tokens fence stale results. Sidekiq retries are disabled; five database-owned attempts use exponential backoff plus jitter and honor Retry-After (values beyond one day require operator attention). Operators may grant up to three fresh budgets without changing identity.

Admission limits are 200 active operations, 50 outstanding claims, 100 queued Redis messages and two Sidekiq threads per process. Use one dedicated Redis database. The Redis Lua producer implements Sidekiq's JSON queue protocol to enforce the physical bound atomically, including stale deliveries. Do not enqueue OperationJob through other producers.

No exactly-once execution is claimed. Completion is durable locally; repeat delivery is safe only because the fictional supplier retains idempotency keys, rejects changed payloads and supports authoritative lookup. Providers without those guarantees can require manual review of ambiguous acceptance. Stale work or a provider outage can pause progress until services recover.

## Webhooks and statements (slice 3)

The webhook signature is HMAC-SHA256 over `timestamp.raw_bytes`, with a five-minute tolerance in either direction and constant-time comparison. Receipt commits the unique event and outbox intent before HTTP 202. Duplicate event IDs require identical bytes. Supplier versions are authoritative: higher wins, lower is ignored, equal must agree. Unknown references and conflicts require manual review; retry the same event operation after resolving its cause.

The simulator sends real signed HTTP events through `POST /emit` with `key`, `id`, `status` and `version` (supplier bearer token required). Its receiver is fixed to loopback at APP_PORT (default 3000).

Upload `demo/dirty-statement.csv` through the authenticated dashboard. Imports accept UTF-8, four exact headers and one record per physical line, bounded to 512 KiB, 2,000 data rows, 2,048 bytes per line and 256 bytes per field. Multiline quoted records are rejected. Findings are immutable observations of local state at import time; repeated identical bytes return the same import. No order updates occur. Exports prefix potentially executable spreadsheet cells with an apostrophe. Invalid files retain bounded partial provenance and an explicit failed state.
