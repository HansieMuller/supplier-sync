abort "Synthetic demo seeds are development/test only" unless Rails.env.development? || Rails.env.test?
CatalogueSync.create!.run!
