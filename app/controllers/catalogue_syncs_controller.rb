class CatalogueSyncsController < ApplicationController
  def create
    CatalogueSync.create!.run!
    redirect_to root_path, notice: "Catalogue synchronized."
  rescue SupplierClient::Permanent, SupplierClient::Transient => e
    redirect_to root_path, alert: e.message
  end
end
