-- Add optional canonical inventory subcategories without changing existing
-- product, stock, billing, or clinic ownership data.
ALTER TABLE inventory_products
  ADD COLUMN IF NOT EXISTS subcategory_key TEXT,
  ADD COLUMN IF NOT EXISTS subcategory TEXT;

CREATE INDEX IF NOT EXISTS inventory_products_subcategory_search_index
  ON inventory_products (clinic_id, subcategory_key)
  WHERE deleted_at IS NULL AND is_archived = false;
