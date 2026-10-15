require "csv"

module StatementExport
  # Spreadsheet applications can execute formulas even in quoted CSV cells.
  def self.cell(value)
    text = value.to_s
    text.match?(/\A(?:[=+\-@\t\r\n]|\s+[=+\-@])/) ? "'#{text}" : text
  end

  def self.csv(import)
    CSV.generate do |csv|
      csv << %w[line reference code detail source]
      import.statement_rows.includes(:findings).find_each do |row|
        row.findings.each do |finding|
          csv << [row.line_number, row.fields["reference"], finding.code, finding.detail, row.source].map { |value| cell(value) }
        end
      end
    end
  end
end
