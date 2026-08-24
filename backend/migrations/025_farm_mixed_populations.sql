-- Preserve mixed-species farm-unit populations and treatment targeting in the
-- production database. Existing unit and treatment records are not rewritten.

CREATE TABLE IF NOT EXISTS farm_unit_populations (
  farm_unit_population_id UUID PRIMARY KEY,
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  farm_id UUID NOT NULL REFERENCES farms(farm_id) ON DELETE RESTRICT,
  farm_unit_id UUID NOT NULL REFERENCES farm_units(farm_unit_id) ON DELETE RESTRICT,
  species_id TEXT NOT NULL CHECK (length(btrim(species_id)) BETWEEN 1 AND 120),
  breed_id TEXT,
  male_count INTEGER NOT NULL DEFAULT 0 CHECK (male_count >= 0),
  female_count INTEGER NOT NULL DEFAULT 0 CHECK (female_count >= 0),
  unknown_count INTEGER NOT NULL DEFAULT 0 CHECK (unknown_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS farm_unit_populations_group_unique
  ON farm_unit_populations
  (clinic_id, farm_unit_id, lower(btrim(species_id)), lower(btrim(coalesce(breed_id, ''))));

CREATE INDEX IF NOT EXISTS farm_unit_populations_unit_index
  ON farm_unit_populations (clinic_id, farm_id, farm_unit_id);

-- A legacy unit becomes one population group. Counts remain zero because the
-- backend did not previously store a reliable sex/population breakdown.
INSERT INTO farm_unit_populations
  (farm_unit_population_id, clinic_id, farm_id, farm_unit_id,
   species_id, breed_id, male_count, female_count, unknown_count)
SELECT gen_random_uuid(), u.clinic_id, u.farm_id, u.farm_unit_id,
       btrim(u.species), nullif(btrim(u.breed), ''), 0, 0, 0
  FROM farm_units u
 WHERE nullif(btrim(u.species), '') IS NOT NULL
   AND NOT EXISTS (
     SELECT 1
       FROM farm_unit_populations p
      WHERE p.clinic_id = u.clinic_id
        AND p.farm_unit_id = u.farm_unit_id
   );

ALTER TABLE farm_treatment_records
  ADD COLUMN IF NOT EXISTS target_scope TEXT NOT NULL DEFAULT 'EntireUnit',
  ADD COLUMN IF NOT EXISTS target_population_ids UUID[] NOT NULL DEFAULT '{}'::uuid[];

UPDATE farm_treatment_records
   SET target_scope = 'EntireUnit',
       target_population_ids = '{}'::uuid[]
 WHERE target_scope IS NULL;

ALTER TABLE farm_treatment_records
  DROP CONSTRAINT IF EXISTS farm_treatment_records_target_scope_check;

ALTER TABLE farm_treatment_records
  ADD CONSTRAINT farm_treatment_records_target_scope_check
  CHECK (target_scope IN ('EntireUnit', 'SelectedGroups'));

ALTER TABLE farm_treatment_records
  DROP CONSTRAINT IF EXISTS farm_treatment_records_target_groups_check;

ALTER TABLE farm_treatment_records
  ADD CONSTRAINT farm_treatment_records_target_groups_check
  CHECK (
    (target_scope = 'EntireUnit' AND cardinality(target_population_ids) = 0)
    OR
    (target_scope = 'SelectedGroups' AND cardinality(target_population_ids) > 0)
  );

ALTER TABLE farm_unit_populations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS farm_unit_populations_tenant_policy ON farm_unit_populations;
CREATE POLICY farm_unit_populations_tenant_policy ON farm_unit_populations
  USING (current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true));
