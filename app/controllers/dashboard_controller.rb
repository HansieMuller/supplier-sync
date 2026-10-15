class DashboardController < ApplicationController
  def show
    @order_count = PurchaseOrder.count
    @products = Product.order(:sku).limit(50)
    @orders = PurchaseOrder.includes(:operation).order(id: :desc).limit(20)
    @operations = Operation.order(id: :desc).limit(15)
    @counts = Operation.group(:state).count
    @imports = StatementImport.order(id: :desc).limit(5)
    @findings = Finding.includes(statement_row: :statement_import).order(id: :desc).limit(25)
    @finding_count = Finding.count
  end
end
