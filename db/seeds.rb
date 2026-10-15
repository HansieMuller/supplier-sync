abort "Synthetic demo seeds are development/test only" unless Rails.env.development? || Rails.env.test?
# Seed durable work rather than making setup depend on a running HTTP provider.
CatalogueSync.schedule!
puts "Synthetic catalogue synchronization scheduled. Start bin/dev to process it."
