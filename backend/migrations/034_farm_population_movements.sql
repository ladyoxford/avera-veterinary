-- Durable, tenant-scoped population deltas for mortality and animal purchases.
-- Existing farm populations are preserved and are not rewritten.

CREATE TABLE IF NOT EXISTS farm_population_movements (
  farm_population_movement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  farm_id UUID NOT NULL REFERENCES farms(farm_id) ON DELETE RESTRICT,
  farm_unit_id UUID NOT NULL REFERENCES farm_units(farm_unit_id) ON DELETE RESTRICT,
  farm_unit_population_id UUID NOT NULL
    REFERENCES farm_unit_populations(farm_unit_population_id) ON DELETE RESTRICT,
  submission_id UUID NOT NULL,
  movement_type TEXT NOT NULL CHECK (movement_type IN ('mortality', 'purchase')),
  sex TEXT NOT NULL CHECK (sex IN ('male', 'female', 'unknown')),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  occurred_at TIMESTAMPTZ NOT NULL,
  source TEXT,
  notes TEXT,
  created_by UUID NOT NULL REFERENCES users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT farm_population_movements_submission_unique
    UNIQUE (clinic_id, submission_id)
);

CREATE INDEX IF NOT EXISTS farm_population_movements_unit_index
  ON farm_population_movements
  (clinic_id, farm_id, farm_unit_id, occurred_at DESC);

ALTER TABLE farm_population_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS farm_population_movements_tenant_policy
  ON farm_population_movements;
CREATE POLICY farm_population_movements_tenant_policy
  ON farm_population_movements
  USING (
    current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true)
  );
