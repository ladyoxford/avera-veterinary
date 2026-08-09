import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { authenticate, requirePermission } from '../middleware/auth.js';
import { permissions } from '../security/permissions.js';
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
      if (previousPath && previousPath !== path) await app.profilePhotoStorage.remove(previousPath);
      return { profilePhotoUrl: await app.profilePhotoStorage.signedUrl(path) };
    } catch (error) {
      return reply.code(error.statusCode ?? 500).send({ error: error.code ?? 'profile_photo_upload_failed', message: error.statusCode ? error.message : 'The profile photo could not be uploaded.' });
    }
  });

  app.delete('/api/v1/me/profile-photo', { preHandler: [authenticate] }, async (request) => {
    const current = (await app.pool.query('SELECT profile_photo_path FROM staff_profiles WHERE user_id = $1', [request.auth.userId])).rows[0]?.profile_photo_path;
    await app.pool.query('UPDATE staff_profiles SET profile_photo_path = NULL, updated_at = now() WHERE user_id = $1', [request.auth.userId]);
    await app.profilePhotoStorage.remove(current);
    return {};
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
    const users = await withTenantTransaction(app.pool, request.auth, async (client) => (
      await client.query(
        `${clinicUserSelect}
          WHERE u.clinic_id = $1 AND u.deleted_at IS NULL
          ORDER BY u.full_name LIMIT 100`,
        [request.auth.clinicId],
      )
    )).rows;
    return { users: await Promise.all(users.map(async (user) => {
      const profilePhotoUrl = await app.profilePhotoStorage.signedUrl(user.profilePhotoPath);
      delete user.profilePhotoPath;
      return { ...user, profilePhotoUrl };
    })) };
  });

  app.get('/api/v1/users/:userId', { preHandler: [authenticate, requirePermission(permissions.usersView)] }, async (request, reply) => {
    if (!request.auth.clinicId) return clinicContextRequired(reply);
    const user = await withTenantTransaction(app.pool, request.auth, async (client) => (
      await client.query(
        `${clinicUserSelect}
          WHERE u.user_id = $1 AND u.clinic_id = $2 AND u.deleted_at IS NULL`,
        [request.params.userId, request.auth.clinicId],
      )
    )).rows[0];
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
