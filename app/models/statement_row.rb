class StatementRow < ApplicationRecord
  belongs_to :statement_import
  has_many :findings, dependent: :restrict_with_exception

  def flag!(code, detail)
    findings.create_or_find_by!(code: code) { |finding| finding.detail = detail }
  end
end
