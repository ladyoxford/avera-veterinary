CREATE TYPE sync_operation_status AS ENUM ('Received', 'Applied', 'Conflict', 'Rejected');

CREATE TABLE sync_operations (
  operation_id UUID PRIMARY KEY,
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
  device_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  local_timestamp TIMESTAMPTZ NOT NULL,
  base_version BIGINT NOT NULL DEFAULT 0,
  payload JSONB NOT NULL,
  status sync_operation_status NOT NULL DEFAULT 'Received',
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  applied_at TIMESTAMPTZ,
  error_summary TEXT,
  UNIQUE (clinic_id, operation_id)
);

CREATE INDEX sync_operations_clinic_status_idx ON sync_operations(clinic_id, status, received_at);
ALTER TABLE sync_operations ENABLE ROW LEVEL SECURITY;
CREATE POLICY sync_operations_tenant_policy ON sync_operations USING (
  current_setting('avera.is_platform_owner', true) = 'true' OR clinic_id::text = current_setting('avera.clinic_id', true)
);
