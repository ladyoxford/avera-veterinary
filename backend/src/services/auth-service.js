import { hashPassword, validatePassword, verifyPassword } from '../security/passwords.js';
import { hashToken, issueRefreshToken } from '../security/tokens.js';
import { effectivePermissions } from '../security/permissions.js';
import { clinicAccess } from '../security/clinic-access.js';
import { writeAudit } from '../audit/audit-service.js';

const lockMinutes = 15;
const maxFailures = 5;

export class AuthService {
  constructor({ pool, environment, app }) {
    this.pool = pool;
    this.environment = environment;
    this.app = app;
    this.mfaService = null;
  }

  setMfaService(service) {
    this.mfaService = service;
  }

  async signIn({ email, password, deviceName, platform, ipAddress, userAgent }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query('SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL', [email.trim().toLowerCase()]);
      let user = result.rows[0];
      if (user?.status === 'Locked' && user.locked_until && user.locked_until <= new Date()) {
        await client.query("UPDATE users SET status = 'Active', failed_login_count = 0, locked_until = NULL WHERE user_id = $1", [user.user_id]);
        user = { ...user, status: 'Active', failed_login_count: 0, locked_until: null };
      }
      if (!user) {
        await client.query('COMMIT');
        return authenticationFailure(401, 'invalid_credentials', 'Invalid credentials or inactive account.', 'user_not_found');
      }
      if (user.status === 'PendingActivation' || !user.password_hash) {
        await client.query('COMMIT');
        return authenticationFailure(
          403,
          'account_activation_required',
          'Activate this account using the secure link sent after clinic approval.',
          'account_pending_activation',
        );
      }
      if (!(await verifyPassword(password, user.password_hash))) {
        if (user.status === 'Active') await this.#recordFailure(client, user, ipAddress);
        await client.query('COMMIT');
        return authenticationFailure(401, 'invalid_credentials', 'Invalid credentials or inactive account.', 'password_mismatch');
      }
      if (user.status !== 'Active' || (user.locked_until && user.locked_until > new Date())) {
        await client.query('COMMIT');
        return authenticationFailure(403, 'account_restricted', 'This account is not currently available.', `account_${user.status.toLowerCase()}`);
      }
      if (user.clinic_id) {
        const access = await clinicAccess(client, user);
        if (!access.allowed) {
          await client.query('COMMIT');
          const isClinicFailure = access.reason.startsWith('clinic_');
          return authenticationFailure(
            403,
            isClinicFailure ? 'clinic_restricted' : 'membership_restricted',
            isClinicFailure ? 'This clinic is not currently available.' : 'Your clinic membership is not currently active.',
            access.reason,
          );
        }
      }
      const mfa = await client.query(
        'SELECT enabled FROM user_mfa_settings WHERE user_id = $1',
        [user.user_id],
      );
      if (mfa.rows[0]?.enabled === true) {
        const challenge = await this.mfaService.createLoginChallenge(client, user, {
          deviceName,
          platform,
          ipAddress,
          userAgent,
        });
        await client.query('COMMIT');
        return { ok: true, session: challenge };
      }
      const permissions = await effectivePermissions(client, user);
      const device = await client.query(
        'INSERT INTO devices (user_id, device_name, platform) VALUES ($1,$2,$3) RETURNING device_id',
        [user.user_id, deviceName ?? null, platform ?? null],
      );
      const refresh = issueRefreshToken();
      const expiresAt = new Date(Date.now() + this.environment.REFRESH_TOKEN_TTL_DAYS * 86_400_000);
      const session = await client.query(
        `INSERT INTO sessions (user_id, device_id, refresh_token_hash, expires_at, ip_address, user_agent)
         VALUES ($1,$2,$3,$4,$5,$6) RETURNING session_id`,
        [user.user_id, device.rows[0].device_id, refresh.hash, expiresAt, ipAddress ?? null, userAgent ?? null],
      );
      await client.query('UPDATE users SET last_login_at = now(), failed_login_count = 0, locked_until = NULL, updated_at = now() WHERE user_id = $1', [user.user_id]);
      await writeAudit(client, { clinicId: user.clinic_id, actingUserId: user.user_id, targetType: 'User', targetId: user.user_id, action: 'auth.login_success', sessionId: session.rows[0].session_id, deviceId: device.rows[0].device_id, ipAddress });
      await client.query('COMMIT');
      return { ok: true, session: await this.#tokenPair({ user, permissions, sessionId: session.rows[0].session_id, refreshToken: refresh.raw }) };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async refresh(refreshToken, ipAddress) {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT s.session_id, s.user_id, u.* FROM sessions s JOIN users u ON u.user_id = s.user_id
          WHERE s.refresh_token_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > now()`,
        [hashToken(refreshToken)],
      );
      const row = result.rows[0];
      if (!row) return null;
      if (row.status !== 'Active') {
        return { restricted: true, code: 'ACCOUNT_SUSPENDED' };
      }
      if (!(await clinicAccess(client, row)).allowed) return null;
      const permissions = await effectivePermissions(client, row);
      const replacement = issueRefreshToken();
      await client.query('UPDATE sessions SET refresh_token_hash = $1, last_used_at = now(), ip_address = $2 WHERE session_id = $3', [replacement.hash, ipAddress ?? null, row.session_id]);
      return await this.#tokenPair({ user: row, permissions, sessionId: row.session_id, refreshToken: replacement.raw });
    } finally {
      client.release();
    }
  }

  async signOut(sessionId, userId, allDevices = false) {
    const sql = allDevices
      ? 'UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL'
      : 'UPDATE sessions SET revoked_at = now() WHERE session_id = $1 AND user_id = $2 AND revoked_at IS NULL';
    await this.pool.query(sql, allDevices ? [userId] : [sessionId, userId]);
  }

  async sessions(userId) {
    return (await this.pool.query('SELECT session_id, device_id, created_at, last_used_at, expires_at, revoked_at, ip_address FROM sessions WHERE user_id = $1 ORDER BY last_used_at DESC', [userId])).rows;
  }

  async changePassword({ user, sessionId, currentPassword, newPassword, ipAddress }) {
    const validationError = validatePassword(newPassword);
    if (validationError) throw new Error(validationError);
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query('SELECT * FROM users WHERE user_id = $1 FOR UPDATE', [user.userId])).rows[0];
      if (!row || !(await verifyPassword(currentPassword, row.password_hash))) throw new Error('Current password is incorrect.');
      await client.query('UPDATE users SET password_hash = $1, requires_password_change = false, updated_at = now() WHERE user_id = $2', [await hashPassword(newPassword), row.user_id]);
      await client.query('UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND session_id <> $2 AND revoked_at IS NULL', [row.user_id, sessionId]);
      await writeAudit(client, { clinicId: row.clinic_id, actingUserId: row.user_id, targetType: 'User', targetId: row.user_id, action: 'auth.password_changed', sessionId, ipAddress });
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async currentUser(user, permissions) {
    return this.#publicUser(user, permissions, await this.#workspace(user));
  }

  async completeMfaSignIn(client, user, context) {
    const access = await clinicAccess(client, user);
    if (!access.allowed) throw new Error('Clinic access is not active.');
    const permissions = await effectivePermissions(client, user);
    const device = await client.query(
      'INSERT INTO devices (user_id, device_name, platform) VALUES ($1,$2,$3) RETURNING device_id',
      [user.user_id, context.deviceName ?? null, context.platform ?? null],
    );
    const refresh = issueRefreshToken();
    const expiresAt = new Date(Date.now() + this.environment.REFRESH_TOKEN_TTL_DAYS * 86_400_000);
    const session = await client.query(
      `INSERT INTO sessions (user_id, device_id, refresh_token_hash, expires_at, ip_address, user_agent)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING session_id`,
      [user.user_id, device.rows[0].device_id, refresh.hash, expiresAt, context.ipAddress ?? null, context.userAgent ?? null],
    );
    await writeAudit(client, {
      clinicId: user.clinic_id,
      actingUserId: user.user_id,
      targetType: 'User',
      targetId: user.user_id,
      action: 'auth.mfa_login_success',
      sessionId: session.rows[0].session_id,
      deviceId: device.rows[0].device_id,
      ipAddress: context.ipAddress,
    });
    return this.#tokenPair({
      user,
      permissions,
      sessionId: session.rows[0].session_id,
      refreshToken: refresh.raw,
    });
  }

  async #recordFailure(client, user, ipAddress) {
    const failures = user.failed_login_count + 1;
    const lockedUntil = failures >= maxFailures ? new Date(Date.now() + lockMinutes * 60_000) : null;
    await client.query(
      `UPDATE users
          SET failed_login_count = $1,
              locked_until = $2::timestamptz,
              status = CASE WHEN $2::timestamptz IS NULL THEN status ELSE 'Locked'::account_status END
        WHERE user_id = $3`,
      [failures, lockedUntil, user.user_id],
    );
    await writeAudit(client, { clinicId: user.clinic_id, actingUserId: user.user_id, targetType: 'User', targetId: user.user_id, action: 'auth.login_failed', ipAddress, success: false });
  }

  async #tokenPair({ user, permissions, sessionId, refreshToken }) {
    const accessToken = this.app.jwt.sign({ userId: user.user_id, accountType: user.account_type, clinicId: user.clinic_id, sessionId }, { expiresIn: this.environment.ACCESS_TOKEN_TTL_SECONDS });
    return { accessToken, refreshToken, expiresIn: this.environment.ACCESS_TOKEN_TTL_SECONDS, user: await this.#publicUser(user, permissions, await this.#workspace(user)) };
  }

  async #publicUser(user, permissions, workspace) {
    const role = user.role_id ? (await this.pool.query(
      `SELECT role_id, code, name
         FROM roles
        WHERE role_id = $1
          AND deleted_at IS NULL
          AND clinic_id IS NOT DISTINCT FROM $2`,
      [user.role_id, user.clinic_id],
    )).rows[0] : null;
    const profile = (await this.pool.query(
      `SELECT professional_title, veterinary_license_number, profile_photo_path
         FROM staff_profiles
        WHERE user_id = $1`,
      [user.user_id],
    )).rows[0] ?? {};
    const profilePhotoUrl = await this.app.profilePhotoStorage.signedUrl(profile.profile_photo_path);
    return publicUser(user, permissions, workspace, role, {
      professionalTitle: profile.professional_title ?? null,
      veterinaryLicenseNumber: profile.veterinary_license_number ?? null,
      profilePhotoUrl,
    });
  }

  async #workspace(user) {
    if (!user.clinic_id) return { clinicId: null, clinicName: 'AVERA Platform', clinicStatus: 'Active', subscriptionPlan: null };
    const clinic = await this.pool.query('SELECT name, status, subscription_plan FROM clinics WHERE clinic_id = $1 AND deleted_at IS NULL', [user.clinic_id]);
    const value = clinic.rows[0];
    return { clinicId: user.clinic_id, clinicName: value?.name ?? 'AVERA Clinic', clinicStatus: value?.status ?? 'Inactive', subscriptionPlan: value?.subscription_plan ?? null };
  }
}

function authenticationFailure(status, code, message, internalReason) {
  return { ok: false, status, code, message, internalReason };
}

export function publicUser(user, permissions, workspace = {}, role = null, profile = {}) {
  return { userId: user.user_id, clinicId: user.clinic_id, fullName: user.full_name, email: user.email, phone: user.phone ?? null, accountType: user.account_type, status: user.status, roleId: role?.role_id ?? user.role_id ?? null, roleCode: role?.code ?? null, roleName: role?.name ?? null, role: role ? { id: role.role_id, code: role.code, name: role.name } : null, permissions, ...profile, ...workspace };
}
