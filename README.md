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
