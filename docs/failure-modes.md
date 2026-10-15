# Failure modes and evidence

Run `bin/rails test` for behavior tests; they use actual PostgreSQL and a loopback Puma supplier. Concurrency cases disable transactional test wrapping, use separate checked-out connections and synchronize with queues/barriers, not timing sleeps. Clock-controlled retry assertions avoid waiting for backoff. The provider's deliberate acceptance delay is the timeout being tested.

| Failure / invariant | Executable evidence |
| --- | --- |
| Catalogue pagination, interruption and checkpoint resume | `test/models/integration_test.rb`: catalogue pages; page checkpoint survives interruption |
| Repeated/invalid cursor | Same file: page checkpoint rejects repeated/URL cursors |
| Terminal pages 49/50 and unfinished page 51 at the finite cap | `test/models/catalogue_sync_test.rb`: real HTTP feed through ordinary job claims/completion |
| Same key, changed payload before and after acceptance | Same file: same-key conflict; identity retained after rejection |
| HTTP 422 versus 429/503; Retry-After dates, malformed and excessive values | Same file + `test/models/operations_test.rb`: validation, scheduling, parsing and exhaustion |
| Business changes and outbox rollback; another session cannot see uncommitted data | `operations_test.rb`: rollback and other-session visibility |
| Competing dispatchers and workers | `CompetingTransactionsTest`: one claim and one attempt |
| 200 active / 50 outstanding / 100 queued race boundaries | Same class: admission, outstanding claims, atomic Redis capacity |
| Both enqueue crash windows; enqueue is not completion | `OperationsTest`: before/after enqueue exceptions and stale recovery |
| Duplicate jobs, old queued tokens and late running results | Same class: duplicate delivery; replacement delivery; abandoned-claim fencing |
| Retry exhaustion, terminal catalogue failure and operator budget limits | Same class: exhausted/manual review; catalogue no-order subject; retry limit |
| Order total exceeds numeric storage range | `OperationsTest`: valid price/quantity overflow rejected before business/outbox insertion |
| Real acceptance followed by response timeout and lookup recovery | Same class plus `bin/smoke`; one received `order_posts`, two `order_lookups` (initial miss and recovery), one accepted order |
| Accepted-key POST replay remains visible without another supplier order | `integration_test.rb` and `bin/smoke`: two real HTTP POSTs, two received requests, one supplier order/reference |
| Webhook tampering, old/future timestamp, duplicate/reused IDs, malformed JSON/types/UTF-8 | `test/integration/webhooks_test.rb` |
| Receipt-before-acknowledgement; outbox-capacity rollback | Same file; concurrent receipt in `CompetingTransactionsTest` |
| Newer, older, same/conflicting version and unknown reference | Same file; simultaneous different versions in `CompetingTransactionsTest` |
| Simulator shipment lookup agrees with webhook; equal-version conflict rejected | `bin/smoke` |
| Signed events sent over actual HTTP and consumed by actual Sidekiq | `bin/smoke` |
| Dirty references/status/currency/decimal totals and conflicting duplicates | `test/models/statements_test.rb` + synthetic `demo/dirty-statement.csv` |
| File/line/field/row/encoding/NUL limits; failed provenance | `statements_test.rb`: strict limits and repeat NUL file |
| Repeat and simultaneous identical file imports create no duplicate findings | Same file + `CompetingTransactionsTest` |
| CSV formula protection; authenticated upload/export and upload body cap | `statements_test.rb` + `test/integration/dashboard_test.rb` |
| Operator auth and actual CSRF enforcement | `dashboard_test.rb` + `webhooks_test.rb` |
| Actual queue path, complete processes and loopback HTTP | `bin/smoke`, also a mandatory GitHub Actions step |

No mock or inline-only test is offered as proof of Sidekiq delivery. Unit behavior tests call the job directly to exercise deterministic branches; the separate smoke proves the configured Redis/Sidekiq/process boundary. It does not establish arbitrary crash timing, high availability, provider retention outside the simulator or production load capacity.
