require Rails.root.join("lib/demo_config")
DemoConfig.load! unless Rails.env.production?
