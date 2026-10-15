class OperationsController < ApplicationController
  def update
    Operation.find(params[:id]).retry_by_operator!
    redirect_to root_path, notice: "Retry scheduled with the original operation identity."
  rescue ArgumentError, Operation::CapacityExceeded => e
    redirect_to root_path, alert: e.message
  end
end
