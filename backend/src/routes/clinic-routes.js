import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { hasPermission, permissions } from '../security/permissions.js';
import { ensureDefaultClinicRoles } from '../security/default-clinic-roles.js';
import { z } from 'zod';

const changeRoleSchema = z.object({ roleId: z.string().uuid() });
const inviteStaffSchema = z.object({
  fullName: z.string().trim().min(1).max(160),
  email: z.string().trim().email().max(254),
  phone: z.string().trim().max(80).nullish(),
  professionalTitle: z.string().trim().min(1).max(160),
  roleId: z.string().uuid(),
});
const selfProfileSchema = z.object({
  fullName: z.string().trim().min(1).max(160),
  phone: z.string().trim().max(80).nullish(),
  veterinaryLicenseNumber: z.string().trim().max(120).nullish(),
});
const profilePhotoSchema = z.object({
  contentType: z.enum(['image/jpeg', 'image/png']),
  data: z.string().min(1),
});
const clinicSettingsSchema = z.object({
  name: z.string().trim().min(2).max(160),
  email: z.string().trim().email().max(254).nullish(),
  phone: z.string().trim().max(80).nullish(),
  address: z.string().trim().max(240).nullish(),
  city: z.string().trim().max(120).nullish(),
  country: z.string().trim().max(120).nullish(),
  timeZone: z.string().trim().min(1).max(120),
});
const workDaySchema = z.object({
  weekday: z.enum(['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']),
  isOpen: z.boolean(),
  openingTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).nullish(),
  closingTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).nullish(),
  breakStart: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).nullish(),
  breakEnd: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).nullish(),
}).superRefine((day, context) => {
  if (day.isOpen && (!day.openingTime || !day.closingTime || day.openingTime >= day.closingTime)) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Open days need valid opening and closing times.' });
  }
});
const clinicWorkHoursSchema = z.object({
  timeZone: z.string().trim().min(1).max(120),
  isEnabled: z.boolean(),
  days: z.array(workDaySchema).length(7).refine((days) => new Set(days.map((day) => day.weekday)).size === 7),
});
const clinicBrandAssetSchema = z.object({
  kind: z.literal('logo'),
  contentType: z.enum(['image/jpeg', 'image/png']),
  data: z.string().min(1),
});
const clinicThemeColorSchema = z.object({ color: z.string().regex(/^#[0-9A-Fa-f]{6}$/) });

const defaultClinicWorkDays = [
  ...['monday', 'tuesday', 'wednesday', 'thursday', 'friday'].map((weekday) => ({ weekday, isOpen: true, openingTime: '08:00', closingTime: '18:00' })),
  { weekday: 'saturday', isOpen: true, openingTime: '09:00', closingTime: '14:00' },
  { weekday: 'sunday', isOpen: false },
];

const clinicUserSelect = `
  SELECT u.user_id AS "userId", u.full_name AS "fullName", u.email, u.phone,
         u.account_type AS "accountType", u.status,
         u.role_id AS "roleId", r.code AS "roleCode", r.name AS "roleName",
         sp.professional_title AS "professionalTitle",
         sp.veterinary_license_number AS "veterinaryLicenseNumber",
         sp.profile_photo_path AS "profilePhotoPath",
         sp.staff_number AS "staffNumber",
         CASE WHEN r.role_id IS NULL THEN NULL ELSE
           json_build_object('id', r.role_id, 'code', r.code, 'name', r.name)
         END AS role,
         cm.membership_status AS "membershipStatus",
         u.last_login_at AS "lastLoginAt", u.created_at AS "createdAt"
    FROM users u
    LEFT JOIN roles r
      ON r.role_id = u.role_id
     AND r.clinic_id = u.clinic_id
     AND r.deleted_at IS NULL
    LEFT JOIN clinic_memberships cm
      ON cm.user_id = u.user_id
     AND cm.clinic_id = u.clinic_id
     AND cm.deleted_at IS NULL
    LEFT JOIN staff_profiles sp ON sp.user_id = u.user_id`;

export async function changeClinicUserRole(client, context) {
  const actor = (
    await client.query(
      `SELECT r.code AS role_code
         FROM users u
         JOIN clinic_memberships cm
           ON cm.user_id = u.user_id
          AND cm.clinic_id = u.clinic_id
          AND cm.deleted_at IS NULL
         JOIN roles r
           ON r.role_id = cm.role_id
          AND r.clinic_id = cm.clinic_id
          AND r.deleted_at IS NULL
        WHERE u.user_id = $1
          AND u.clinic_id = $2
          AND u.status = 'Active'
          AND cm.membership_status = 'Active'
          AND u.deleted_at IS NULL`,
      [context.actorUserId, context.clinicId],
    )
  ).rows[0];
  if (actor?.role_code !== 'clinic_administrator') {
    throw routeError(
      403,
      'role_management_forbidden',
      'Only an active Clinic Administrator can change staff roles.',
    );
  }

  const target = (
    await client.query(
      `SELECT u.user_id, u.role_id, r.code AS role_code, r.name AS role_name
         FROM users u
         LEFT JOIN roles r ON r.role_id = u.role_id
        WHERE u.user_id = $1 AND u.clinic_id = $2 AND u.deleted_at IS NULL
        FOR UPDATE OF u`,
      [context.targetUserId, context.clinicId],
    )
  ).rows[0];
  if (!target) {
    throw routeError(404, 'staff_not_found', 'Staff member was not found in this clinic.');
  }

  const role = (
    await client.query(
      `SELECT role_id, code, name
         FROM roles
        WHERE role_id = $1 AND clinic_id = $2 AND deleted_at IS NULL`,
      [context.roleId, context.clinicId],
    )
  ).rows[0];
  if (!role) {
    throw routeError(400, 'invalid_clinic_role', 'The selected role is not available in this clinic.');
  }

  if (target.role_code === 'clinic_administrator' && role.code !== 'clinic_administrator') {
    const active = await client.query(
      `SELECT count(*)::int AS count
         FROM users u
         JOIN roles r ON r.role_id = u.role_id AND r.clinic_id = u.clinic_id
         JOIN clinic_memberships cm
           ON cm.user_id = u.user_id AND cm.clinic_id = u.clinic_id
        WHERE u.clinic_id = $1
          AND u.status = 'Active'
          AND cm.membership_status = 'Active'
          AND r.code = 'clinic_administrator'
          AND u.deleted_at IS NULL
          AND cm.deleted_at IS NULL`,
      [context.clinicId],
    );
    if (active.rows[0].count <= 1) {
      throw routeError(409, 'final_clinic_administrator', 'The final active Clinic Administrator cannot be demoted.');
    }
  }

  const accountType = role.code === 'clinic_administrator' ? 'ClinicAdministrator' : 'ClinicStaff';
  await client.query(
    `UPDATE users
        SET role_id = $1, account_type = $2, updated_at = now(), updated_by = $3
      WHERE user_id = $4 AND clinic_id = $5`,
    [role.role_id, accountType, context.actorUserId, target.user_id, context.clinicId],
  );
  await client.query(
    `UPDATE clinic_memberships
        SET role_id = $1, updated_at = now(), updated_by = $2
      WHERE user_id = $3 AND clinic_id = $4 AND deleted_at IS NULL`,
    [role.role_id, context.actorUserId, target.user_id, context.clinicId],
  );
  await writeAudit(client, {
    clinicId: context.clinicId,
    actingUserId: context.actorUserId,
    targetType: 'User',
    targetId: target.user_id,
    action: 'staff.role_changed',
    previousSummary: {
      roleId: target.role_id,
      roleCode: target.role_code,
      roleName: target.role_name,
    },
    newSummary: { roleId: role.role_id, roleCode: role.code, roleName: role.name },
    sessionId: context.sessionId,
    ipAddress: context.ipAddress,
  });
  return {
    userId: target.user_id,
    accountType,
    roleId: role.role_id,
    roleCode: role.code,
    roleName: role.name,
    role: { id: role.role_id, code: role.code, name: role.name },
  };
}

export async function clinicRoutes(app) {
  app.get('/api/v1/clinic/settings', { preHandler: [authenticate, requirePermission(permissions.clinicSettingsView)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const clinic = (await client.query(
        `SELECT c.clinic_id AS "clinicId", c.name, c.email, c.phone, c.address,
                c.city, c.country, c.time_zone AS "timeZone",
                coalesce(cb.primary_color, '#087F7B') AS "themeColor",
                cb.logo_path AS "logoPath",
                c.patient_number_prefix AS "patientNumberPrefix",
                c.patient_number_sequence_length AS "patientNumberSequenceLength",
                c.patient_number_reset_yearly AS "patientNumberResetYearly",
                c.patient_number_prefix_reviewed AS "patientNumberPrefixReviewed"
           FROM clinics c
           LEFT JOIN clinic_branding cb ON cb.clinic_id = c.clinic_id
          WHERE c.clinic_id = $1 AND c.deleted_at IS NULL`,
        [request.auth.clinicId],
      )).rows[0];
      if (!clinic) return reply.code(404).send({ error: 'clinic_not_found', message: 'The active clinic was not found.' });
      return { clinic: {
        ...clinic,
        logoReference: clinic.logoPath,
        logoUrl: await app.profilePhotoStorage.signedUrl(clinic.logoPath),
      } };
    });
  });

  app.patch('/api/v1/clinic/settings', { preHandler: [authenticate, requirePermission(permissions.clinicSettingsEdit)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    const parsed = clinicSettingsSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Review the clinic information and try again.' });
    await withTenantTransaction(app.pool, request.auth, async (client) => {
      const previous = (await client.query('SELECT name, email, phone, address, city, country, time_zone FROM clinics WHERE clinic_id = $1 FOR UPDATE', [request.auth.clinicId])).rows[0];
      if (!previous) throw Object.assign(new Error('Clinic not found'), { statusCode: 404 });
      const value = parsed.data;
      await client.query(
        `UPDATE clinics SET name=$1, email=$2, phone=$3, address=$4, city=$5,
          country=$6, time_zone=$7, updated_at=now(), updated_by=$8
          WHERE clinic_id=$9`,
        [value.name, value.email || null, value.phone || null, value.address || null, value.city || null, value.country || null, value.timeZone, request.auth.userId, request.auth.clinicId],
      );
      await writeAudit(client, { clinicId: request.auth.clinicId, actingUserId: request.auth.userId, targetType: 'Clinic', targetId: request.auth.clinicId, action: 'clinic.settings_updated', previousSummary: previous, newSummary: value, sessionId: request.auth.sessionId, ipAddress: request.ip });
    });
    return { updated: true };
  });

  app.get('/api/v1/clinic/work-hours', { preHandler: [authenticate] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      await client.query(
        `INSERT INTO clinic_work_hours (clinic_id, time_zone, days)
         SELECT clinic_id, time_zone, $2::jsonb FROM clinics WHERE clinic_id=$1
         ON CONFLICT (clinic_id) DO NOTHING`,
        [request.auth.clinicId, JSON.stringify(defaultClinicWorkDays)],
      );
      const value = (await client.query('SELECT clinic_id AS "clinicId", time_zone AS "timeZone", is_enabled AS "isEnabled", days FROM clinic_work_hours WHERE clinic_id=$1', [request.auth.clinicId])).rows[0];
      return { workHours: value };
    });
  });

  app.put('/api/v1/clinic/work-hours', { preHandler: [authenticate] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    if (!hasPermission(request, permissions.clinicWorkHoursManage) && !hasPermission(request, permissions.clinicSettingsEdit)) {
      return reply.code(403).send({ error: 'permission_required', message: 'You do not have permission to manage clinic work hours.' });
    }
    const parsed = clinicWorkHoursSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Review the work hours and try again.' });
    return withTenantTransaction(app.pool, request.auth, async (client) => {
      const previous = (await client.query('SELECT time_zone, is_enabled, days FROM clinic_work_hours WHERE clinic_id=$1 FOR UPDATE', [request.auth.clinicId])).rows[0] ?? null;
      const value = parsed.data;
      await client.query(
        `INSERT INTO clinic_work_hours (clinic_id,time_zone,is_enabled,days,updated_by)
         VALUES ($1,$2,$3,$4::jsonb,$5)
         ON CONFLICT (clinic_id) DO UPDATE SET time_zone=EXCLUDED.time_zone,
           is_enabled=EXCLUDED.is_enabled, days=EXCLUDED.days, updated_at=now(), updated_by=EXCLUDED.updated_by`,
        [request.auth.clinicId, value.timeZone, value.isEnabled, JSON.stringify(value.days), request.auth.userId],
      );
      await client.query('UPDATE clinics SET time_zone=$1, updated_at=now(), updated_by=$2 WHERE clinic_id=$3', [value.timeZone, request.auth.userId, request.auth.clinicId]);
      await writeAudit(client, { clinicId: request.auth.clinicId, actingUserId: request.auth.userId, targetType: 'ClinicWorkHours', targetId: request.auth.clinicId, action: 'clinic.work_hours_updated', previousSummary: previous, newSummary: value, sessionId: request.auth.sessionId, ipAddress: request.ip });
      return { workHours: { clinicId: request.auth.clinicId, ...value } };
    });
  });

  app.post('/api/v1/clinic/branding', { preHandler: [authenticate, requirePermission(permissions.clinicSettingsEdit)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    const parsed = clinicBrandAssetSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_clinic_branding', message: 'Choose a JPEG or PNG image.' });
    try {
      const bytes = Buffer.from(parsed.data.data, 'base64');
      const path = await app.profilePhotoStorage.uploadBrandAsset({ clinicId: request.auth.clinicId, kind: parsed.data.kind, contentType: parsed.data.contentType, bytes });
      const column = 'logo_path';
      const previous = await withTenantTransaction(app.pool, request.auth, async (client) => {
        const oldPath = (await client.query(`SELECT ${column} AS path FROM clinic_branding WHERE clinic_id=$1`, [request.auth.clinicId])).rows[0]?.path;
        await client.query(
          `INSERT INTO clinic_branding (clinic_id, ${column}, updated_by) VALUES ($1,$2,$3)
           ON CONFLICT (clinic_id) DO UPDATE SET ${column}=EXCLUDED.${column}, updated_at=now(), updated_by=EXCLUDED.updated_by`,
          [request.auth.clinicId, path, request.auth.userId],
        );
        await writeAudit(client, { clinicId: request.auth.clinicId, actingUserId: request.auth.userId, targetType: 'ClinicBranding', targetId: request.auth.clinicId, action: `clinic.${parsed.data.kind}_updated`, previousSummary: { path: oldPath ?? null }, newSummary: { path }, sessionId: request.auth.sessionId, ipAddress: request.ip });
        return oldPath;
      });
      if (previous && previous !== path) await app.profilePhotoStorage.remove(previous);
      return { reference: path, url: await app.profilePhotoStorage.signedUrl(path) };
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({ error: error.code ?? 'clinic_branding_upload_failed', message: error.statusCode ? error.message : 'The clinic image could not be uploaded.' });
    }
  });

  app.patch('/api/v1/clinic/theme-color', { preHandler: [authenticate, requirePermission(permissions.clinicSettingsEdit)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    const parsed = clinicThemeColorSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_theme_color', message: 'Choose a valid clinic theme color.' });
    const color = parsed.data.color.toUpperCase();
    await withTenantTransaction(app.pool, request.auth, async (client) => {
      const previous = (await client.query('SELECT primary_color FROM clinic_branding WHERE clinic_id=$1 FOR UPDATE', [request.auth.clinicId])).rows[0]?.primary_color ?? '#087F7B';
      await client.query(`INSERT INTO clinic_branding (clinic_id,primary_color,updated_by) VALUES ($1,$2,$3) ON CONFLICT (clinic_id) DO UPDATE SET primary_color=EXCLUDED.primary_color,updated_at=now(),updated_by=EXCLUDED.updated_by`, [request.auth.clinicId, color, request.auth.userId]);
      await writeAudit(client, { clinicId: request.auth.clinicId, actingUserId: request.auth.userId, targetType: 'ClinicBranding', targetId: request.auth.clinicId, action: 'clinic.theme_color_updated', previousSummary: { color: previous }, newSummary: { color }, sessionId: request.auth.sessionId, ipAddress: request.ip });
    });
    return { color };
  });

  app.get('/api/v1/me/profile', { preHandler: [authenticate] }, async (request, reply) => {
    const profile = (await app.pool.query(
      `${clinicUserSelect} WHERE u.user_id = $1 AND u.deleted_at IS NULL`,
      [request.auth.userId],
    )).rows[0];
    if (!profile) return reply.code(404).send({ error: 'profile_not_found', message: 'Your profile could not be found.' });
    const profilePhotoUrl = await app.profilePhotoStorage.signedUrl(profile.profilePhotoPath);
    delete profile.profilePhotoPath;
    return { profile: { ...profile, clinicName: request.auth.clinicId ? (await app.pool.query('SELECT name FROM clinics WHERE clinic_id = $1', [request.auth.clinicId])).rows[0]?.name : 'AVERA Platform', profilePhotoUrl } };
  });

  app.patch('/api/v1/me/profile', { preHandler: [authenticate] }, async (request, reply) => {
    const parsed = selfProfileSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Review your name and phone number.' });
    const value = parsed.data;
    await withTenantTransaction(app.pool, request.auth, async (client) => {
      const current = (await client.query('SELECT full_name, phone FROM users WHERE user_id = $1 FOR UPDATE', [request.auth.userId])).rows[0];
      if (!current) throw Object.assign(new Error('Profile not found'), { statusCode: 404, code: 'profile_not_found' });
      await client.query('UPDATE users SET full_name = $1, phone = $2, updated_at = now(), updated_by = $3 WHERE user_id = $3', [value.fullName, value.phone || null, request.auth.userId]);
      if (request.auth.clinicId) {
        await client.query(
          `INSERT INTO staff_profiles (user_id, clinic_id, veterinary_license_number)
           VALUES ($1, $2, $3)
           ON CONFLICT (user_id) DO UPDATE SET veterinary_license_number = EXCLUDED.veterinary_license_number, updated_at = now()`,
          [request.auth.userId, request.auth.clinicId, value.veterinaryLicenseNumber || null],
        );
      }
      await writeAudit(client, { clinicId: request.auth.clinicId, actingUserId: request.auth.userId, targetType: 'User', targetId: request.auth.userId, action: 'profile.updated', previousSummary: { fullName: current.full_name, phone: current.phone }, newSummary: { fullName: value.fullName, phone: value.phone || null }, sessionId: request.auth.sessionId, ipAddress: request.ip });
    });
    return { user: await app.authService.currentUser((await app.pool.query('SELECT * FROM users WHERE user_id = $1', [request.auth.userId])).rows[0], request.auth.permissions) };
  });

  app.post('/api/v1/me/profile-photo', { preHandler: [authenticate] }, async (request, reply) => {
    const parsed = profilePhotoSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_profile_photo', message: 'Choose a JPEG or PNG image.' });
    let bytes;
    try { bytes = Buffer.from(parsed.data.data, 'base64'); } catch (_) { return reply.code(400).send({ error: 'invalid_profile_photo', message: 'The selected image could not be read.' }); }
    try {
      const previousPath = (await app.pool.query('SELECT profile_photo_path FROM staff_profiles WHERE user_id = $1', [request.auth.userId])).rows[0]?.profile_photo_path;
      const path = await app.profilePhotoStorage.upload({ clinicId: request.auth.clinicId, userId: request.auth.userId, contentType: parsed.data.contentType, bytes });
      await app.pool.query(
        `INSERT INTO staff_profiles (user_id, clinic_id, profile_photo_path)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO UPDATE SET profile_photo_path = EXCLUDED.profile_photo_path, updated_at = now()`,
        [request.auth.userId, request.auth.clinicId, path],
      );
      if (previousPath && previousPath !== path) {
        void Promise.resolve().then(() => app.profilePhotoStorage.remove(previousPath)).catch(() => {
          request.log.warn({ userId: request.auth.userId }, 'Previous profile photo cleanup failed.');
        });
      }
      return { profilePhotoUrl: await app.profilePhotoStorage.signedUrl(path) };
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({ error: error.code ?? 'profile_photo_upload_failed', message: error.statusCode ? error.message : 'The profile photo could not be uploaded.' });
    }
  });

  app.delete('/api/v1/me/profile-photo', { preHandler: [authenticate] }, async (request, reply) => {
    const current = await withTenantTransaction(app.pool, request.auth, async (client) => {
      const profile = (await client.query(
        'SELECT profile_photo_path FROM staff_profiles WHERE user_id = $1 FOR UPDATE',
        [request.auth.userId],
      )).rows[0];
      await client.query(
        'UPDATE staff_profiles SET profile_photo_path = NULL, updated_at = now() WHERE user_id = $1',
        [request.auth.userId],
      );
      await writeAudit(client, {
        clinicId: request.auth.clinicId,
        actingUserId: request.auth.userId,
        targetType: 'User',
        targetId: request.auth.userId,
        action: 'profile.photo_removed',
        previousSummary: { hadPhoto: Boolean(profile?.profile_photo_path) },
        newSummary: { hasPhoto: false },
        sessionId: request.auth.sessionId,
        ipAddress: request.ip,
      });
      return profile?.profile_photo_path;
    });
    // New uploads have unique paths, so delayed cleanup cannot remove a replacement.
    void Promise.resolve().then(() => app.profilePhotoStorage.remove(current)).catch(() => {
      request.log.warn(
        { userId: request.auth.userId },
        'Profile photo reference cleared; object cleanup will need retrying.',
      );
    });
    return reply.code(204).send();
  });
  app.post('/api/v1/users/invitations', { config: { rateLimit: { max: 10, timeWindow: '1 hour' } }, preHandler: [authenticate, requirePermission(permissions.usersCreate)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    if (request.auth.accountType !== 'ClinicAdministrator') {
      return reply.code(403).send({ error: 'staff_invitation_forbidden', message: 'Only a Clinic Administrator may invite staff.' });
    }
    const parsed = inviteStaffSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'Please review the staff invitation.' });
    try {
      const invitation = await app.activationService.inviteStaff({
        ...parsed.data, clinicId: request.auth.clinicId,
        actorUserId: request.auth.userId, sessionId: request.auth.sessionId,
        ipAddress: request.ip,
      });
      reply.code(201);
      return { invitation };
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({
        error: error.code ?? 'staff_invitation_failed',
        message: error.statusCode ? error.message : 'The staff invitation could not be created.',
      });
    }
  });

  app.post('/api/v1/users/:userId/invitation/resend', { config: { rateLimit: { max: 5, timeWindow: '1 hour' } }, preHandler: [authenticate, requirePermission(permissions.usersCreate)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    if (request.auth.accountType !== 'ClinicAdministrator') {
      return reply.code(403).send({ error: 'staff_invitation_forbidden', message: 'Only a Clinic Administrator may resend staff invitations.' });
    }
    try {
      return { invitation: await app.activationService.resendStaff({
        targetUserId: request.params.userId, clinicId: request.auth.clinicId,
        actorUserId: request.auth.userId, sessionId: request.auth.sessionId,
        ipAddress: request.ip,
      }) };
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({
        error: error.code ?? 'staff_invitation_resend_failed',
        message: error.statusCode ? error.message : 'The staff invitation could not be resent.',
      });
    }
  });

  app.get('/api/v1/users', { preHandler: [authenticate, requirePermission(permissions.usersView)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    const usersResult = await withTenantTransaction(app.pool, request.auth, async (client) => (
      await client.query(
        `${clinicUserSelect}
          WHERE u.clinic_id = $1 AND u.deleted_at IS NULL
          ORDER BY u.full_name LIMIT 100`,
        [request.auth.clinicId],
      )
    ));
    const users = usersResult.rows;
    return { users: await Promise.all(users.map(async (user) => {
      const profilePhotoUrl = await app.profilePhotoStorage.signedUrl(user.profilePhotoPath);
      delete user.profilePhotoPath;
      return { ...user, profilePhotoUrl };
    })) };
  });

  app.get('/api/v1/users/:userId', { preHandler: [authenticate, requirePermission(permissions.usersView)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    const userResult = await withTenantTransaction(app.pool, request.auth, async (client) => (
      await client.query(
        `${clinicUserSelect}
          WHERE u.user_id = $1 AND u.clinic_id = $2 AND u.deleted_at IS NULL`,
        [request.params.userId, request.auth.clinicId],
      )
    ));
    const user = userResult.rows[0];
    if (!user) return reply.code(404).send({ error: 'staff_not_found', message: 'Staff member was not found in this clinic.' });
    const profilePhotoUrl = await app.profilePhotoStorage.signedUrl(user.profilePhotoPath);
    delete user.profilePhotoPath;
    return { user: { ...user, profilePhotoUrl } };
  });

  app.get('/api/v1/roles', { preHandler: [authenticate, requirePermission(permissions.usersView)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    const roles = await withTenantTransaction(app.pool, request.auth, async (client) => {
      await ensureDefaultClinicRoles(client, {
        clinicId: request.auth.clinicId,
        actorUserId: request.auth.userId,
      });
      return (await client.query(
        `SELECT role_id AS "roleId", code AS "roleCode", name AS "roleName",
                json_build_object('id', role_id, 'code', code, 'name', name) AS role,
                description, is_system_role AS "isSystemRole"
           FROM roles
          WHERE clinic_id = $1
            AND code <> 'clinic_administrator'
            AND deleted_at IS NULL
          ORDER BY name`,
        [request.auth.clinicId],
      )).rows;
    });
    return { roles };
  });

  app.get('/api/v1/permissions', { preHandler: [authenticate] }, async () => ({ permissions: Object.values(permissions) }));

  app.patch('/api/v1/users/:userId/role', { preHandler: [authenticate, requirePermission(permissions.staffRolesManage)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    if (request.auth.accountType !== 'ClinicAdministrator') {
      return reply.code(403).send({ error: 'forbidden', message: 'Only a Clinic Administrator may change staff roles.' });
    }
    if (request.params.userId === request.auth.userId) {
      return reply.code(403).send({ error: 'self_role_change_forbidden', message: 'You cannot change your own Clinic Administrator role.' });
    }
    const parsed = changeRoleSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'validation_error', message: 'A valid role is required.' });
    try {
      const user = await withTenantTransaction(app.pool, request.auth, (client) => changeClinicUserRole(client, {
        clinicId: request.auth.clinicId,
        actorUserId: request.auth.userId,
        targetUserId: request.params.userId,
        roleId: parsed.data.roleId,
        sessionId: request.auth.sessionId,
        ipAddress: request.ip,
      }));
      return { user };
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({
        error: error.code ?? 'role_change_failed',
        message: error.statusCode ? error.message : 'The role change could not be completed.',
      });
    }
  });
}

function clinicContextRequired(reply) {
  return reply.code(400).send({ error: 'clinic_context_required', message: 'Select a clinic workspace first.' });
}

function routeError(statusCode, code, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.code = code;
  return error;
}
