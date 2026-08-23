-- Farm billing and package-unit inventory remain part of the canonical invoice
-- and inventory domains. Existing quantities are preserved as base stock.

ALTER TABLE inventory_products
  ADD COLUMN IF NOT EXISTS base_unit_label TEXT NOT NULL DEFAULT 'unit',
  ADD COLUMN IF NOT EXISTS active_ingredient TEXT,
  ADD COLUMN IF NOT EXISTS dosage_and_route TEXT,
  ADD COLUMN IF NOT EXISTS withdrawal_meat TEXT,
  ADD COLUMN IF NOT EXISTS withdrawal_milk TEXT,
  ADD COLUMN IF NOT EXISTS withdrawal_eggs TEXT,
  ADD COLUMN IF NOT EXISTS warnings TEXT,
  ADD COLUMN IF NOT EXISTS is_sellable BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS inventory_product_units (
  product_unit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  inventory_product_id UUID NOT NULL
    REFERENCES inventory_products(inventory_product_id) ON DELETE RESTRICT,
  unit_label TEXT NOT NULL CHECK (length(btrim(unit_label)) BETWEEN 1 AND 80),
  is_base_unit BOOLEAN NOT NULL DEFAULT false,
  conversion_to_base INTEGER NOT NULL CHECK (conversion_to_base > 0),
  selling_price NUMERIC(12, 2) NOT NULL CHECK (selling_price >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revision INTEGER NOT NULL DEFAULT 1,
  CHECK (NOT is_base_unit OR conversion_to_base = 1)
);

CREATE UNIQUE INDEX IF NOT EXISTS inventory_product_units_label_unique
  ON inventory_product_units
  (clinic_id, inventory_product_id, lower(btrim(unit_label)));

CREATE UNIQUE INDEX IF NOT EXISTS inventory_product_units_one_base
  ON inventory_product_units (clinic_id, inventory_product_id)
  WHERE is_base_unit;

INSERT INTO inventory_product_units
  (clinic_id, inventory_product_id, unit_label, is_base_unit,
   conversion_to_base, selling_price)
SELECT clinic_id, inventory_product_id,
       COALESCE(NULLIF(btrim(base_unit_label), ''), 'unit'), true, 1,
       selling_price
  FROM inventory_products p
 WHERE deleted_at IS NULL
   AND NOT EXISTS (
     SELECT 1 FROM inventory_product_units u
      WHERE u.clinic_id = p.clinic_id
        AND u.inventory_product_id = p.inventory_product_id
   );

CREATE TABLE IF NOT EXISTS farms (
  farm_id UUID PRIMARY KEY,
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  name TEXT NOT NULL,
  client_name TEXT,
  client_phone TEXT,
  status TEXT NOT NULL DEFAULT 'Active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS farm_units (
  farm_unit_id UUID PRIMARY KEY,
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  farm_id UUID NOT NULL REFERENCES farms(farm_id) ON DELETE RESTRICT,
  name TEXT NOT NULL,
  unit_type TEXT,
  species TEXT,
  breed TEXT,
  status TEXT NOT NULL DEFAULT 'Active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS farm_treatment_records (
  farm_treatment_record_id UUID PRIMARY KEY,
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  farm_id UUID NOT NULL REFERENCES farms(farm_id) ON DELETE RESTRICT,
  farm_unit_id UUID REFERENCES farm_units(farm_unit_id) ON DELETE RESTRICT,
  treatment_type TEXT NOT NULL,
  product_name TEXT,
  occurred_at TIMESTAMPTZ NOT NULL,
  animals_covered INTEGER CHECK (animals_covered IS NULL OR animals_covered > 0),
  billable_amount NUMERIC(12, 2) CHECK (billable_amount IS NULL OR billable_amount >= 0),
  cost_snapshot NUMERIC(12, 2) CHECK (cost_snapshot IS NULL OR cost_snapshot >= 0),
  notes TEXT,
  created_by UUID REFERENCES users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE invoices
  ALTER COLUMN owner_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS context_type TEXT NOT NULL DEFAULT 'patient',
  ADD COLUMN IF NOT EXISTS farm_id UUID REFERENCES farms(farm_id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS farm_visit_date DATE,
  ADD COLUMN IF NOT EXISTS client_name_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS client_phone_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS inventory_deducted_at TIMESTAMPTZ;

ALTER TABLE invoice_line_items
  ADD COLUMN IF NOT EXISTS farm_unit_id UUID REFERENCES farm_units(farm_unit_id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS source_treatment_record_id UUID
    REFERENCES farm_treatment_records(farm_treatment_record_id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS inventory_product_id UUID
    REFERENCES inventory_products(inventory_product_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS product_unit_id UUID
    REFERENCES inventory_product_units(product_unit_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS display_unit_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS conversion_to_base_snapshot INTEGER,
  ADD COLUMN IF NOT EXISTS base_quantity_snapshot INTEGER,
  ADD COLUMN IF NOT EXISTS unit_cost_snapshot NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS product_name_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS batch_number_snapshot TEXT,
  ADD COLUMN IF NOT EXISTS expiry_date_snapshot DATE;

CREATE UNIQUE INDEX IF NOT EXISTS invoice_line_items_treatment_unique
  ON invoice_line_items (clinic_id, source_treatment_record_id)
  WHERE source_treatment_record_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS inventory_reorder_requests (
  reorder_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  inventory_product_id UUID NOT NULL
    REFERENCES inventory_products(inventory_product_id) ON DELETE RESTRICT,
  product_unit_id UUID REFERENCES inventory_product_units(product_unit_id) ON DELETE SET NULL,
  supplier_snapshot TEXT,
  requested_quantity INTEGER NOT NULL CHECK (requested_quantity > 0),
  requested_unit_snapshot TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'Requested',
  requested_by UUID NOT NULL REFERENCES users(user_id),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS farms_clinic_index ON farms (clinic_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS farm_units_farm_index ON farm_units (clinic_id, farm_id);
CREATE INDEX IF NOT EXISTS farm_treatments_farm_index
  ON farm_treatment_records (clinic_id, farm_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS invoices_farm_index
  ON invoices (clinic_id, farm_id, issued_at DESC) WHERE farm_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS reorder_requests_product_index
  ON inventory_reorder_requests (clinic_id, inventory_product_id, requested_at DESC);

ALTER TABLE inventory_product_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE farms ENABLE ROW LEVEL SECURITY;
ALTER TABLE farm_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE farm_treatment_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_reorder_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventory_product_units_tenant_policy ON inventory_product_units;
CREATE POLICY inventory_product_units_tenant_policy ON inventory_product_units
  USING (current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true));
DROP POLICY IF EXISTS farms_tenant_policy ON farms;
CREATE POLICY farms_tenant_policy ON farms
  USING (current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true));
DROP POLICY IF EXISTS farm_units_tenant_policy ON farm_units;
CREATE POLICY farm_units_tenant_policy ON farm_units
  USING (current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true));
DROP POLICY IF EXISTS farm_treatments_tenant_policy ON farm_treatment_records;
CREATE POLICY farm_treatments_tenant_policy ON farm_treatment_records
  USING (current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true));
DROP POLICY IF EXISTS reorder_requests_tenant_policy ON inventory_reorder_requests;
CREATE POLICY reorder_requests_tenant_policy ON inventory_reorder_requests
  USING (current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true));
