export async function writeAudit(client, event) {
  await client.query(
    `INSERT INTO audit_logs (clinic_id, acting_user_id, target_type, target_id, action, previous_summary, new_summary, session_id, device_id, ip_address, success, reason)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
    [event.clinicId, event.actingUserId, event.targetType, event.targetId, event.action, event.previousSummary ?? null, event.newSummary ?? null, event.sessionId ?? null, event.deviceId ?? null, event.ipAddress ?? null, event.success ?? true, event.reason ?? null],
  );
}
