CREATE INDEX invoices_clinic_number_idx ON invoices(clinic_id, invoice_number);
CREATE INDEX patients_clinic_breed_idx ON patients(clinic_id, breed);
CREATE INDEX laboratory_clinic_test_idx ON laboratory_reports(clinic_id, test_type, requested_at DESC);
CREATE INDEX stock_movements_clinic_occurred_idx ON stock_movements(clinic_id, occurred_at DESC);
