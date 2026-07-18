export async function clinicAccess(client, user) {
  if (!user.clinic_id) return { allowed: true };
  const result = await client.query(
    `SELECT cm.membership_status, c.status AS clinic_status
       FROM clinics c
       LEFT JOIN clinic_memberships cm
         ON cm.clinic_id = c.clinic_id AND cm.user_id = $1 AND cm.deleted_at IS NULL
      WHERE c.clinic_id = $2 AND c.deleted_at IS NULL`,
    [user.user_id, user.clinic_id],
  );
  const value = result.rows[0];
  if (!value || !value.membership_status) return { allowed: false, reason: 'membership_missing' };
  if (value.membership_status !== 'Active') return { allowed: false, reason: `membership_${value.membership_status.toLowerCase()}` };
  if (value.clinic_status !== 'Active') return { allowed: false, reason: `clinic_${value.clinic_status.toLowerCase()}` };
  return { allowed: true };
}
