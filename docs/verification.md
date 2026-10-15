# Verification evidence

Verified locally on **15 October 2026**, macOS arm64, Ruby 4.0.7 / Rails 8.1.4. These are observed commands and results, not unrun test claims.

| Command / check | Observed result |
| --- | --- |
| `docker compose up -d --wait` | PostgreSQL 17.11 and Redis 8.2.10 healthy, loopback ports 55439/56379 |
| `PGPORT=55439 PGUSER=supplier_sync REDIS_URL=redis://127.0.0.1:56379/12 bin/setup` | DB preparation and synthetic catalogue seed scheduling succeeded |
| Same environment, `bin/ci` | All six gates passed: database, behavior/concurrency, autoload, real-process smoke, Brakeman, dependency audit |
| `bin/rails test` inside that campaign | 40 tests, 335 assertions, zero failures/errors/skips |
| `bin/smoke` inside that campaign | Actual PostgreSQL, Redis, Sidekiq, dispatcher, Rails HTTP receiver and simulator passed |
| Smoke acceptance timeout | First attempt recorded Net::ReadTimeout; lookup recovered; provider observed one POST and one accepted synthetic order |
| Smoke webhook and reconciliation | Actual signed HTTP receipt and queued application passed; duplicate event/file processing preserved counts |
| `bundle exec brakeman --no-pager` | Zero security warnings/errors |
| `bundle exec bundler-audit check --update` | No known gem vulnerabilities reported by the fetched advisory database |
| `bin/rails demo:reset` with workers stopped and standalone supplier | Old synthetic records removed; one fresh pending catalogue operation confirmed by independent readback |
| `bin/rails zeitwerk:check` / `bin/rails routes` | Eager loading and route listing passed |
| `bin/rails db:rollback STEP=1` then `bin/rails db:migrate` | Webhook/statement migration reversed and reapplied successfully on local synthetic development DB |
| Chromium browser interaction against running app | Authenticated order/scenario forms and CSV upload exercised; actual dashboard and timeout timeline screenshots captured |
| Responsive inspection | 390px viewport, 390px document width after correcting grid overflow |

The earlier slices were committed after focused tests, including real competing PostgreSQL sessions and a local TCP HTTP simulator. An agent review found terminal catalogue and malformed-input defects; separate correction commits and regressions preserve that review history.

The baseline main GitHub Actions run passed. The implementation workflow runs the Rails tests, eager loading, real-process smoke, Brakeman and dependency audit; inspect the [Actions page](https://github.com/HansieMuller/supplier-sync/actions) for the current branch/PR result. Hosted status is reported separately from this dated local evidence.

Publication review started from an empty workspace. The Rails scaffold, original implementation, generated app screenshots and fictional fixtures are the only project materials. Runtime files, local secrets, logs, database dumps and Serena metadata are ignored. `script/audit_publication.rb` scans reachable history and staged files for configured credential patterns and forbidden paths; it is a heuristic aid, not a guarantee against every possible secret. Commit authorship uses the configured personal Git identity. No employer/customer source material was imported.

Not established: production deployment safety, load capacity, failover behavior, real-provider idempotency retention, independent external security approval or exactly-once execution. The project remains an AI-assisted educational demonstration; an independent audit and replay of failure scenarios remain appropriate before using it in applications.
