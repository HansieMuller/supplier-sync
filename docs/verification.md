# Verification evidence

Verified locally on **15 October 2026**, macOS arm64, Ruby 4.0.7 / Rails 8.1.4. These are observed commands and results, not unrun test claims.

| Command / check | Observed result |
| --- | --- |
| `docker compose up -d --wait` | PostgreSQL 17.11 and Redis 8.2.10 healthy, loopback ports 55439/56379 |
| `PGPORT=55439 PGUSER=supplier_sync REDIS_URL=redis://127.0.0.1:56379/12 bin/setup` | DB preparation and synthetic catalogue seed scheduling succeeded |
| Same environment, `bin/ci` | All six gates passed: database, behavior/concurrency, autoload, real-process smoke, Brakeman, dependency audit |
| Explicit `RAILS_ENV=test bin/rails db:seed`, then `CI=true RAILS_ENV=test bin/rails db:prepare test` | 40 tests / 335 assertions passed with seeded input; test-only cleanup is guarded to the exact test database |
| `bin/rails test` inside that campaign | 40 tests, 335 assertions, zero failures/errors/skips |
| `bin/smoke` inside that campaign | Actual PostgreSQL, Redis, Sidekiq, dispatcher, Rails HTTP receiver and simulator passed |
| Original smoke acceptance timeout | Net::ReadTimeout and one supplier order were observed. The original counter did not count accepted-key replays, so its one-POST claim was not established; the corrected evidence below supersedes that measurement. |
| Smoke webhook and reconciliation | Actual signed HTTP receipt and queued application passed; duplicate event/file processing preserved counts |
| `bundle exec brakeman --no-pager` | Zero security warnings/errors |
| `bundle exec bundler-audit check --update` | No known gem vulnerabilities reported by the fetched advisory database |
| `bin/rails demo:reset` with workers stopped and standalone supplier | Old synthetic records removed; one fresh pending catalogue operation confirmed by independent readback |
| `bin/rails zeitwerk:check` / `bin/rails routes` | Eager loading and route listing passed |
| `bin/rails db:rollback STEP=1` then `bin/rails db:migrate` | Webhook/statement migration reversed and reapplied successfully on local synthetic development DB |
| Chromium browser interaction against running app | Authenticated order/scenario forms and CSV upload exercised; actual dashboard and timeout timeline screenshots captured |
| Responsive inspection | 390px viewport, 390px document width after correcting grid overflow |

The earlier slices were committed after focused tests, including real competing PostgreSQL sessions and a local TCP HTTP simulator. An agent review found terminal catalogue and malformed-input defects; separate correction commits and regressions preserve that review history.

The baseline main GitHub Actions run passed. The first implementation push exposed seed contamination in the fresh test database; explicit test-only isolation corrected it without changing application seeds or weakening assertions. The implementation workflow runs the Rails tests, eager loading, real-process smoke, Brakeman and dependency audit; inspect the [Actions page](https://github.com/HansieMuller/supplier-sync/actions) for the current branch/PR result. Hosted status is reported separately from this dated local evidence.

Publication review started from an empty workspace. The Rails scaffold, original implementation, generated app screenshots and fictional fixtures are the only project materials. Runtime files, local secrets, logs, database dumps and Serena metadata are ignored. `script/audit_publication.rb` scans reachable history and staged files for configured credential patterns and forbidden paths; it is a heuristic aid, not a guarantee against every possible secret. Commit authorship uses the configured personal Git identity. No employer/customer source material was imported.

## Targeted audit corrections — 15 October 2026

The supplied independent source audit reviewed `e3d322e9dac185eba45d5446e2496db2470112a4`. Its author did not run the whole app/browser journey; its narrow probes and hosted-log review were explicitly limited. This pass reproduced both control-flow/instrumentation findings locally and implemented the four bounded outcomes. The corrected branch still awaits final independent review; this report is author verification, not external certification or production approval.

All behavior commands below use `PGHOST=127.0.0.1 PGPORT=55439 PGUSER=supplier_sync REDIS_URL=redis://127.0.0.1:56379/13`. The scripts were inspected first. Tests own `supplier_sync_test` and Redis DB 13; smoke owns `supplier_sync_smoke` and DB 14 on this project's Compose endpoint. No development reset was run during this pass.

| Finding / command | Actual result |
| --- | --- |
| C1: `bin/rails test test/models/catalogue_sync_test.rb` before the fix | Page 50 failed with operation `failed` instead of `completed`; pages 49 and 51 behaved as expected. |
| C1: `bin/rails test test/models/catalogue_sync_test.rb test/models/integration_test.rb` after the fix | 9 tests / 50 assertions passed. Real HTTP feeds traverse normal job claims and completion: terminal 49/50 succeed; 51 stops after 50 reads with a pending checkpoint and failed operation. |
| C2: replay regression before the fix | Two real HTTP POSTs returned one supplier reference/order but the old counter reported 1 instead of 2. |
| C2: `bin/rails test test/models/integration_test.rb test/models/operations_test.rb` | 27 tests / 224 assertions passed, including replay counting, timeout lookup recovery and the 429-once scenario. |
| C2 compatibility follow-up: same focused command | 28 tests / 228 assertions passed. A retained-ledger regression first reproduced an extra 429; scenario-attempt history is now preserved independently of the new traffic counters. |
| C2: `bin/smoke` | Passed with actual PostgreSQL, Redis, dispatcher, Sidekiq, Rails and HTTP supplier. Timeout recovery: one received POST, two lookups, one accepted supplier order. A separate replay probe adds one supplier order/reference from two counted POSTs. |
| U1/U2: `bin/rails test test/integration/operation_review_test.rb test/integration/webhooks_test.rb` | 10 tests / 117 assertions passed. Old exceptions remain navigable; unknown/equal-version context is read only; an early signed event retries without a new event, digest or operation; lower versions remain ignored and conflicts remain manual review. |
| Final `bin/ci` | 49 tests / 451 assertions, zero failures/errors/skips; eager loading, real-process smoke, Brakeman (zero warnings/errors), and current dependency audit (no known vulnerabilities) passed. |

`/stats` now separates the actual ledger `order_count`, per-key `order_posts` and `order_lookups`. POST measurement includes authenticated valid-key JSON-object requests that replay or conflict with an accepted payload, plus scenario rejections. It excludes requests rejected before this boundary (authentication, size, JSON-object/key parsing). Lookups include misses. Counters start when initialized/reset and do not reconstruct old traffic. These are simulator measurements under its declared contract, not proof of exactly-once execution.

Browser verification used a newly created `supplier_sync_review_20261015` database, dedicated Redis DB 15, loopback app/supplier ports 3111/4571 and a separate ignored supplier ledger. Fixture preparation created two old manual-review events, 20 newer failed operations and 16 newer completed operations. Basic authentication and CSRF were enabled. At **1440×1000** and **390×844**, the operator followed **Need attention → Older exceptions → webhook detail**. Both pages stayed within the viewport width; wide tables scroll inside their panels. Captions/labels were raised from 9–11px to 12px and their pale colors darkened; computed styles confirmed the new values. This is a focused visual check, not a complete accessibility audit.

After real dispatcher/Sidekiq lookup recovery established the early order's reference, the phone browser clicked **Schedule safe retry**. Real Sidekiq completed the same event operation with one operator retry, unchanged body digest and no new event/operation. The simulator had already advanced the recovered order to shipment version 2, so this event correctly became `ignored_duplicate_version`. The equal-version disagreement remained in manual review. Browser console inspection reported no errors.

Actual running-app screenshots:

- Attention list with older exceptions: [desktop](screenshots/attention-desktop.png), [phone](screenshots/attention-phone.png).
- Unknown-reference manual review: [desktop](screenshots/manual-review-desktop.png), [phone](screenshots/manual-review-phone.png).
- [Equal-version conflict with matching local order](screenshots/version-conflict-desktop.png).
- [Same early event after the phone-browser retry](screenshots/webhook-recovered-phone.png).

Hosted CI on the final pushed PR head is reported in the PR after the run completes. The workflow still runs the same complete checks; no assertion or CI gate was removed.

Not established: production deployment safety, load capacity, failover behavior, real-provider idempotency retention, independent external security approval or exactly-once execution. Final independent review of these corrections and failure demonstrations remains pending before using the project in applications. No merge or deployment was performed in this correction pass.
