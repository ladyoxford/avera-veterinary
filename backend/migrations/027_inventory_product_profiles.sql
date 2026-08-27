-- Complete the existing Inventory product profile without changing stock,
-- package units, billing deductions, or clinic ownership.
ALTER TABLE inventory_products
  ADD COLUMN IF NOT EXISTS brand_name TEXT,
  ADD COLUMN IF NOT EXISTS sku TEXT,
  ADD COLUMN IF NOT EXISTS barcode TEXT,
  ADD COLUMN IF NOT EXISTS short_description TEXT,
  ADD COLUMN IF NOT EXISTS detailed_description TEXT,
  ADD COLUMN IF NOT EXISTS dosage_form TEXT,
  ADD COLUMN IF NOT EXISTS pack_size TEXT,
  ADD COLUMN IF NOT EXISTS withdrawal_other TEXT,
  ADD COLUMN IF NOT EXISTS contraindications TEXT,
  ADD COLUMN IF NOT EXISTS adverse_effects TEXT,
  ADD COLUMN IF NOT EXISTS public_display_name TEXT,
  ADD COLUMN IF NOT EXISTS available_to_public BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS inventory_products_catalogue_search_index
  ON inventory_products (clinic_id, lower(name));

CREATE INDEX IF NOT EXISTS inventory_products_public_visibility_index
  ON inventory_products (clinic_id, available_to_public)
  WHERE deleted_at IS NULL AND is_archived = false;
