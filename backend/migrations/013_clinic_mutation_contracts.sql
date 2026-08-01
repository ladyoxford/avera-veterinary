-- Production mutation support for consultations and inventory.
-- Existing rows remain unchanged; submission IDs only protect new writes.

ALTER TABLE consultations
  ADD COLUMN IF NOT EXISTS submission_id UUID,
  ADD COLUMN IF NOT EXISTS prescription_notes TEXT,
  ADD COLUMN IF NOT EXISTS clinician_name_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS consultations_clinic_submission_unique
  ON consultations (clinic_id, submission_id)
  WHERE submission_id IS NOT NULL;

ALTER TABLE inventory_products
  ADD COLUMN IF NOT EXISTS category_key TEXT,
  ADD COLUMN IF NOT EXISTS submission_id UUID,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS revision BIGINT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

UPDATE inventory_products
   SET category_key = CASE
     WHEN lower(category) LIKE '%vaccine%' THEN 'vaccines'
     WHEN lower(category) LIKE '%drug%' OR lower(category) LIKE '%pharmacy%' THEN 'drugs'
     WHEN lower(category) LIKE '%supplement%' THEN 'supplements'
     WHEN lower(category) LIKE '%reagent%' THEN 'laboratory_reagents'
     WHEN lower(category) LIKE '%diagnostic%' OR lower(category) LIKE '%test%' THEN 'diagnostic_test_kits'
     WHEN lower(category) LIKE '%laboratory%' AND lower(category) LIKE '%equipment%' THEN 'laboratory_equipment'
     WHEN lower(category) LIKE '%laboratory%' THEN 'laboratory_consumables'
     WHEN lower(category) LIKE '%surg%' THEN 'surgical_supplies'
     WHEN lower(category) LIKE '%consumable%' THEN 'clinical_consumables'
     WHEN lower(category) LIKE '%food%' THEN 'pet_food'
     WHEN lower(category) LIKE '%accessor%' THEN 'pet_accessories'
     WHEN lower(category) LIKE '%groom%' THEN 'grooming_supplies'
     WHEN lower(category) LIKE '%office%' THEN 'office_supplies'
     WHEN lower(category) LIKE '%equipment%' THEN 'general_equipment'
     ELSE 'other'
   END
 WHERE category_key IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS inventory_clinic_submission_unique
  ON inventory_products (clinic_id, submission_id)
  WHERE submission_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS inventory_clinic_category_key_idx
  ON inventory_products (clinic_id, category_key)
  WHERE deleted_at IS NULL;
