export async function allocateClinicStaffNumber(client, clinicId) {
  await client.query(
    `INSERT INTO clinic_staff_number_sequences (clinic_id, current_value)
     SELECT $1,
            coalesce(max(CASE
              WHEN profile.staff_number ~ '^[0-9]+$'
                THEN profile.staff_number::BIGINT
            END), 0)
       FROM staff_profiles profile
      WHERE profile.clinic_id = $1
     ON CONFLICT (clinic_id) DO NOTHING`,
    [clinicId],
  );
  const sequence = (
    await client.query(
      `UPDATE clinic_staff_number_sequences
          SET current_value = current_value + 1,
              updated_at = now()
        WHERE clinic_id = $1
        RETURNING current_value`,
      [clinicId],
    )
  ).rows[0];
  if (!sequence) {
    throw new Error('Clinic staff number sequence could not be allocated.');
  }
  return String(sequence.current_value).padStart(3, '0');
}
