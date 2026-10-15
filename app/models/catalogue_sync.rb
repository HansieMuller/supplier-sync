class CatalogueSync < ApplicationRecord
  def self.schedule!
    transaction do
      sync = create!
      Operation.admit!(kind: "catalogue_sync", catalogue_sync: sync)
      sync
    end
  end

  # Commit one validated page and its checkpoint together. Interrupted runs resume that cursor.
  def run!(client: SupplierClient.new, guard: nil)
    50.times do
      return if state == "completed"
      page = client.catalogue(cursor)
      items = page.fetch("items")
      next_cursor = page.fetch("next_cursor")
      raise SupplierClient::Permanent, "invalid_page" unless items.is_a?(Array) && items.size.between?(1, 50)
      if next_cursor && (!next_cursor.is_a?(String) || !next_cursor.match?(/\A[A-Za-z0-9-]{1,64}\z/) || seen_cursors.include?(next_cursor) || next_cursor == cursor)
        raise SupplierClient::Permanent, "invalid_cursor"
      end
      transaction do
        guard&.call
        items.each do |item|
          raise SupplierClient::Permanent, "invalid_product" unless item.is_a?(Hash) && item["price"].is_a?(String) && item["price"].match?(/\A[0-9]{1,10}\.[0-9]{2}\z/)
          product = Product.find_or_initialize_by(sku: item.fetch("sku"))
          product.update!(item.slice("name", "currency", "price"))
        end
        update!(cursor: next_cursor, seen_cursors: seen_cursors + [cursor].compact, state: next_cursor ? "pending" : "completed")
      end
    end
    raise SupplierClient::Permanent, "page_limit"
  rescue KeyError, ActiveRecord::RecordInvalid
    raise SupplierClient::Permanent, "invalid_page"
  end
end
