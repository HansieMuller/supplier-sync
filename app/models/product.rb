class Product < ApplicationRecord
  validates :sku, format: { with: /\A[A-Z0-9-]{1,40}\z/ }, uniqueness: true
  validates :name, length: { in: 1..100 }
  validates :currency, inclusion: { in: %w[ZAR USD EUR] }
  validates :price, numericality: { greater_than_or_equal_to: 0, less_than: 10**10 }
end
