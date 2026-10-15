namespace :demo do
  desc "Reset fictional supplier ledger and local application data (stop workers first)"
  task reset: :environment do
    abort "Development/test only" unless Rails.env.development? || Rails.env.test?
    SupplierClient.new.request("POST", "/reset", {})
    PurchaseOrder.delete_all
    CatalogueSync.delete_all
    Product.delete_all
    Rake::Task["db:seed"].invoke
  end
end
