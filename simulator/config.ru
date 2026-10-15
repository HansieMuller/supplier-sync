abort "Simulator is development/test only" unless %w[development test].include?(ENV.fetch("RAILS_ENV", "development"))
require_relative "app"
run SupplierSimulator.new
