-- Preserve records removed from active clinic operations without breaking
-- financial, inventory, or audit relationships.
ALTER TABLE inventory_products
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES users(user_id),
  ADD COLUMN IF NOT EXISTS archive_reason TEXT;

ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS voided_by UUID REFERENCES users(user_id),
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

CREATE INDEX IF NOT EXISTS inventory_products_archive_lookup
  ON inventory_products (clinic_id, archived_at DESC)
  WHERE is_archived = true AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS invoices_voided_lookup
  ON invoices (clinic_id, voided_at DESC)
  WHERE status = 'Voided';
