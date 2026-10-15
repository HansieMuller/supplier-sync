class OrdersController < ApplicationController
  def create
    order = PurchaseOrder.place!(product: Product.find(params.require(:product_id)), quantity: params.require(:quantity), scenario: params.fetch(:scenario, "normal"))
    order.submit!
    redirect_to root_path, notice: "Order accepted by supplier."
  rescue ArgumentError, SupplierClient::Permanent, SupplierClient::Transient => e
    redirect_to root_path, alert: e.message
  end
end
