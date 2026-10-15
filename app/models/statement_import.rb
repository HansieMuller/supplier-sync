require "csv"
require "digest"

class StatementImport < ApplicationRecord
  class InvalidFile < StandardError; end
  MAX_BYTES = 524_288
  MAX_ROWS = 2_000
  MAX_LINE = 2_048
  HEADERS = %w[reference status currency total].freeze
  has_many :statement_rows, dependent: :restrict_with_exception

  # A bounded digest pass gives repeat processing an identity without loading the file.
  # Imports are evidence snapshots; repeating the same bytes returns the existing findings.
  def self.process!(io, filename: "statement.csv")
    io.rewind
    digest, bytes = Digest::SHA256.new, 0
    while (chunk = io.read(16_384))
      bytes += chunk.bytesize
      raise InvalidFile, "File exceeds 512 KiB" if bytes > MAX_BYTES
      digest.update(chunk)
    end
    raise InvalidFile, "Empty file" if bytes.zero?
    io.rewind
    import = create_or_find_by!(digest: digest.hexdigest) { |record| record.filename = File.basename(filename.to_s).first(100).presence || "statement.csv" }
    import.with_lock do
      return import unless import.state == "processing"
      begin
        import.read_rows!(io)
        import.update!(state: "completed")
      rescue InvalidFile => e
        import.update!(state: "failed", error: e.message)
      end
    end
    import
  end

  # One CSV record per physical line is an explicit supplier contract. Quoted multiline
  # fields are rejected, which makes byte/row limits and source line provenance exact.
  def read_rows!(io)
    header = read_line(io, 1)&.delete_prefix("\uFEFF")
    raise InvalidFile, "Headers must be reference,status,currency,total" unless header && CSV.parse_line(header) == HEADERS
    seen = {}
    line_number = 1
    while (line = read_line(io, line_number + 1))
      line_number += 1
      raise InvalidFile, "Too many rows" if line_number - 1 > MAX_ROWS
      row = statement_rows.create!(line_number: line_number, source: line.chomp)
      begin
        values = CSV.parse_line(line, liberal_parsing: false, field_size_limit: 256)
        unless values&.length == 4 && values.all? { |value| value.is_a?(String) && !value.empty? && value.bytesize <= 256 && !value.match?(/[\x00-\x1F\x7F]/) }
          row.flag!("invalid_row", "Exactly four bounded, nonempty fields are required")
          next
        end
        fields = HEADERS.zip(values).to_h
        row.update!(fields: fields)
        reference, status, currency, total = values
        row.flag!("invalid_reference", "Expected SUP- followed by digits") unless reference.match?(/\ASUP-[0-9]{1,10}\z/)
        row.flag!("invalid_status", "Unsupported supplier status") unless %w[accepted shipped delivered].include?(status)
        row.flag!("invalid_currency", "Unsupported currency") unless %w[ZAR USD EUR].include?(currency)
        decimal_valid = total.match?(/\A(?:0|[1-9][0-9]{0,9})\.[0-9]{2}\z/)
        row.flag!("invalid_total", "Expected a positive decimal with two places") unless decimal_valid
        if seen[reference] && seen[reference][:fields] != fields
          row.flag!("conflicting_duplicate", "Conflicts with source line #{seen[reference][:line]}")
        end
        seen[reference] ||= { fields: fields, line: line_number }
        order = PurchaseOrder.find_by(supplier_reference: reference)
        if order.nil?
          row.flag!("unknown_order", "No local order with this supplier reference")
        else
          row.flag!("status_mismatch", "Local status: #{order.state}") if status != order.state
          row.flag!("currency_mismatch", "Local currency: #{order.currency}") if currency != order.currency
          row.flag!("amount_mismatch", "Local total: #{order.total.to_s('F')}") if decimal_valid && BigDecimal(total) != order.total
        end
      rescue CSV::MalformedCSVError
        row.flag!("malformed_csv", "Malformed or oversized CSV field")
      end
    end
  rescue CSV::MalformedCSVError
    raise InvalidFile, "Malformed CSV header"
  end

  def read_line(io, number)
    raw = io.gets(MAX_LINE + 1)
    return unless raw
    raise InvalidFile, "Line #{number} exceeds 2048 bytes" if raw.bytesize > MAX_LINE
    line = raw.dup.force_encoding(Encoding::UTF_8)
    raise InvalidFile, "Line #{number} is not valid UTF-8" unless line.valid_encoding?
    line
  end
end
