CI.run do
  step "Database", "bin/rails db:prepare"
  step "Behavior and competing transactions", "bin/rails test"
  step "Autoloading", "bin/rails zeitwerk:check"
  step "Real process integration", "bin/smoke"
  step "Security scan", "bundle exec brakeman --no-pager"
  step "Dependency audit", "bundle exec bundler-audit check --update"
end
