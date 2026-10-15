require "test_helper"
require "stringio"

class StatementsTest < ActiveSupport::TestCase
  HEADER = "reference,status,currency,total\n"

  def import(text)
    StatementImport.process!(StringIO.new(text), filename: "fictional.csv")
  end

  test "dirty statement preserves provenance and findings without overwriting orders or duplicating on repeat" do
    order = PurchaseOrder.create!(idempotency_key: SecureRandom.uuid, payload: {}, total: "45.00", currency: "ZAR", state: "accepted", supplier_reference: "SUP-1")
    text = File.read(Rails.root.join("demo/dirty-statement.csv"))
    statement = import(text)
    assert_equal "completed", statement.state
    assert_equal 5, statement.statement_rows.count
    assert_equal "SUP-1,shipped,ZAR,49.00", statement.statement_rows.find_by!(line_number: 3).source
    codes = Finding.joins(:statement_row).where(statement_rows: { statement_import_id: statement.id }).pluck(:code)
    %w[conflicting_duplicate unknown_order amount_mismatch status_mismatch currency_mismatch invalid_reference invalid_status invalid_total].each { |code| assert_includes codes, code }
    assert_no_difference ["StatementImport.count", "StatementRow.count", "Finding.count"] do
      assert_equal statement.id, import(text).id
    end
    assert_equal "accepted", order.reload.state
    assert_equal BigDecimal("45.00"), order.total
    exported = CSV.parse(StatementExport.csv(statement))
    assert exported.any? { |row| row[1] == "'=DEMO" }
  end

  test "file, line, field, row and encoding limits are strict" do
    assert_raises(StatementImport::InvalidFile) { import("x" * (StatementImport::MAX_BYTES + 1)) }
    assert_raises(StatementImport::InvalidFile) { import("") }
    statement = import(HEADER + "x" * 2049)
    assert_equal "failed", statement.state
    statement = import(HEADER + "SUP-1,accepted,ZAR,45.00\xFF".b)
    assert_equal "failed", statement.state
    statement = import(HEADER + "SUP-1,accepted,ZAR," + "1" * 257 + "\n")
    assert_equal "completed", statement.state
    assert_includes statement.statement_rows.first.findings.pluck(:code), "malformed_csv"
    statement = import(HEADER + ("SUP-1,accepted,ZAR,45.00\n" * (StatementImport::MAX_ROWS + 1)))
    assert_equal "failed", statement.state
    assert_equal StatementImport::MAX_ROWS, statement.statement_rows.count
  end

  test "malformed rows, unsupported currencies and floating point notation become findings" do
    statement = import(HEADER + "SUP-1,accepted,GBP,4.5e1\n\"broken,quoted\n")
    codes = statement.statement_rows.includes(:findings).flat_map { |row| row.findings.map(&:code) }
    assert_includes codes, "invalid_currency"
    assert_includes codes, "invalid_total"
    assert_includes codes, "malformed_csv"
    assert_equal "failed", import("wrong,headers\n").state
  end

  test "NUL input fails explicitly and repeating it preserves the failed import" do
    text = HEADER + "SUP-1,accepted,ZAR,45.00\x00\n"
    statement = import(text)
    assert_equal "failed", statement.state
    assert_includes statement.error, "NUL"
    assert_equal 0, statement.statement_rows.count
    assert_no_difference ["StatementImport.count", "Finding.count"] do
      assert_equal statement.id, import(text).id
    end
  end

  test "CSV formula protection includes whitespace and control prefixes" do
    ["=1", "+1", "-1", "@SUM(1)", "  =1", "\t=1", "\r=1", "\n=1"].each do |value|
      assert_equal "'#{value}", StatementExport.cell(value)
    end
    assert_equal "SUP-1", StatementExport.cell("SUP-1")
  end
end
