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
