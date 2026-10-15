class ApplicationController < ActionController::Base
  before_action :authenticate_operator

  private

  # One local operator; secure comparisons avoid leaking password prefixes through timing.
  def authenticate_operator
    authenticate_or_request_with_http_basic("SupplierSync local operator") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, "operator") &
        ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("OPERATOR_PASSWORD"))
    end
  end
end
