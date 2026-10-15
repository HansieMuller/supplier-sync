class DashboardController < ApplicationController
  def show
    @products = Product.order(:sku).limit(50)
    @orders = PurchaseOrder.order(id: :desc).limit(50)
  end
end
