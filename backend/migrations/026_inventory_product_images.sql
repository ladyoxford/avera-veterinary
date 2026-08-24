-- Product photos are private, clinic-scoped storage objects. Only their object
-- paths are persisted; API responses provide short-lived signed URLs.
ALTER TABLE inventory_products
  ADD COLUMN IF NOT EXISTS image_path TEXT;
