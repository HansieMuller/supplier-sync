# SupplierSync

A Rails 8 supplier-integration demo exploring reliable background processing, API failure recovery and data reconciliation. It uses original project code and fictional fixtures.

Ruby 4.0.7, Rails 8.1.4 and PostgreSQL 17. Rails 8.1 receives security maintenance through October 2027; review dependency updates before any public deployment.

```sh
bundle install
bin/rails db:prepare
bin/rails server -b 127.0.0.1
bin/rails test
```

This baseline boots a server-rendered dashboard. The implementation branch adds the supplier simulator, durable operations, Sidekiq processing, signed webhooks and statement reconciliation. No paid services or external credentials are needed.

## Development

Developed with AI-assisted tooling. This is a portfolio demo, not a production customer deployment or evidence of operating scale.
