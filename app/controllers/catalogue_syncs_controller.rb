class CatalogueSyncsController < ApplicationController
  def create
    CatalogueSync.schedule!
    redirect_to root_path, notice: "Catalogue synchronization queued."
  rescue Operation::CapacityExceeded => e
    redirect_to root_path, alert: e.message
  end
end
