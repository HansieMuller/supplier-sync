class StatementsController < ApplicationController
  def create
    upload = params.require(:statement)
    raise StatementImport::InvalidFile, "Choose a CSV file" unless upload.respond_to?(:tempfile) && upload.original_filename.to_s.downcase.end_with?(".csv")
    import = StatementImport.process!(upload.tempfile, filename: upload.original_filename)
    redirect_to root_path, notice: "Statement #{import.id}: #{import.state}. Findings preserve source lines."
  rescue StatementImport::InvalidFile => e
    redirect_to root_path, alert: e.message
  end

  def show
    import = StatementImport.find(params[:id])
    send_data StatementExport.csv(import), type: "text/csv; charset=utf-8", filename: "supplier-discrepancies-#{import.id}.csv"
  end
end
