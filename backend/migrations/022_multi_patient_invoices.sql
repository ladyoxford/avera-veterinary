ALTER TABLE invoices
  ADD COLUMN IF NOT EXISTS submission_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS invoices_clinic_submission_unique
  ON invoices (clinic_id, submission_id)
  WHERE submission_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS invoice_line_items (
  invoice_line_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  invoice_id UUID NOT NULL REFERENCES invoices(invoice_id) ON DELETE RESTRICT,
  patient_id UUID REFERENCES patients(patient_id) ON DELETE RESTRICT,
  line_type TEXT NOT NULL DEFAULT 'Service',
  description TEXT NOT NULL,
  quantity NUMERIC(12, 3) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
  line_total NUMERIC(12, 2) NOT NULL CHECK (line_total >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS invoice_line_items_invoice_index
  ON invoice_line_items (clinic_id, invoice_id, created_at);

CREATE INDEX IF NOT EXISTS invoice_line_items_patient_index
  ON invoice_line_items (clinic_id, patient_id, created_at DESC)
  WHERE patient_id IS NOT NULL;

ALTER TABLE invoice_line_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invoice_line_items_tenant_policy ON invoice_line_items;
CREATE POLICY invoice_line_items_tenant_policy ON invoice_line_items
  USING (
    current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true)
  );
