class OperationsController < ApplicationController
  def index
    operations = Operation.needing_attention.order(id: :desc)
    if params.key?(:before)
      cursor = Integer(params[:before].to_s, 10, exception: false)
      raise ActionController::BadRequest, "Invalid operation cursor" unless cursor&.between?(1, 2**63 - 1)
      operations = operations.where("id < ?", cursor)
    end
    # A keyset cursor keeps each read bounded, even when the exception is old.
    @operations = operations.limit(21).to_a
    @has_older = @operations.size > 20
    @operations.pop if @has_older
  end

  def show
    @operation = Operation.find(params[:id])
    @attempts = @operation.attempts.order(:number).limit(100)
    @event = @operation.webhook_event
    @matching_order = PurchaseOrder.find_by(supplier_reference: @event.payload.fetch("reference")) if @event
  end

  def update
    Operation.find(params[:id]).retry_by_operator!
    redirect_to root_path, notice: "Retry scheduled with the original operation identity."
  rescue ArgumentError, Operation::CapacityExceeded => e
    redirect_to root_path, alert: e.message
  end
end
