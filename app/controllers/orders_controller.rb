class OrdersController < ApplicationController
  def create
    order = PurchaseOrder.place!(product: Product.find(params.require(:product_id)), quantity: params.require(:quantity), scenario: params.fetch(:scenario, "normal"))
    redirect_to root_path, notice: "Order queued for supplier submission."
  rescue ArgumentError, Operation::CapacityExceeded => e
    redirect_to root_path, alert: e.message
  end
end
