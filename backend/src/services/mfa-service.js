import {
  decryptSecret,
  encryptSecret,
  generateRecoveryCodes,
  generateTotpSecret,
  hashRecoveryCode,
  hashSecret,
  issueOpaqueToken,
  normalizeRecoveryCode,
  totpUri,
  verifyTotp,
} from '../security/mfa.js';
import { verifyPassword } from '../security/passwords.js';
import { writeAudit } from '../audit/audit-service.js';

const challengeMinutes = 5;
const setupMinutes = 10;
const maximumAttempts = 5;

export class MfaService {
  constructor({ pool, environment, authService }) {
    this.pool = pool;
    this.environment = environment;
    this.authService = authService;
  }

  async status(userId) {
    const result = await this.pool.query(
      'SELECT enabled, verified_at, recovery_codes_generated_at FROM user_mfa_settings WHERE user_id = $1',
      [userId],
    );
    const value = result.rows[0];
    return {
      enabled: value?.enabled === true,
      verifiedAt: value?.verified_at ?? null,
      recoveryCodesGeneratedAt: value?.recovery_codes_generated_at ?? null,
    };
  }

  async beginSetup(auth, password) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const user = (await client.query(
        'SELECT * FROM users WHERE user_id = $1 FOR UPDATE',
        [auth.userId],
      )).rows[0];
      if (!user || user.status !== 'Active' || !(await verifyPassword(password, user.password_hash))) {
        throw new Error('Reauthentication failed.');
      }
      const secret = generateTotpSecret();
      const setupId = cryptoRandomUuid();
      await client.query(
        `INSERT INTO user_mfa_settings
           (user_id, enabled, encrypted_totp_secret, pending_setup_id, pending_secret_expires_at, updated_at)
         VALUES ($1, false, $2, $3, now() + ($4 || ' minutes')::interval, now())
         ON CONFLICT (user_id) DO UPDATE SET
           enabled = false,
           encrypted_totp_secret = EXCLUDED.encrypted_totp_secret,
           pending_setup_id = EXCLUDED.pending_setup_id,
           pending_secret_expires_at = EXCLUDED.pending_secret_expires_at,
           updated_at = now()`,
        [user.user_id, encryptSecret(secret, this.environment.TOTP_ENCRYPTION_KEY), setupId, setupMinutes],
      );
      await writeAudit(client, {
        clinicId: user.clinic_id,
        actingUserId: user.user_id,
        targetType: 'User',
        targetId: user.user_id,
        action: 'security.2fa_setup_started',
        sessionId: auth.sessionId,
      });
      await client.query('COMMIT');
      return { setupId, manualKey: secret, otpauthUri: totpUri(secret, user.email) };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async confirmSetup(auth, setupId, code) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query(
        `SELECT u.*, m.encrypted_totp_secret
           FROM users u JOIN user_mfa_settings m ON m.user_id = u.user_id
          WHERE u.user_id = $1 AND m.pending_setup_id = $2
            AND m.pending_secret_expires_at > now() FOR UPDATE`,
        [auth.userId, setupId],
      )).rows[0];
      if (!row || row.status !== 'Active') throw new Error('The setup request has expired.');
      const secret = decryptSecret(row.encrypted_totp_secret, this.environment.TOTP_ENCRYPTION_KEY);
      if (!verifyTotp(code, secret)) throw new Error('The verification code is invalid.');
      const recoveryCodes = generateRecoveryCodes();
      await client.query('DELETE FROM user_recovery_codes WHERE user_id = $1', [row.user_id]);
      for (const recoveryCode of recoveryCodes) {
        await client.query(
          'INSERT INTO user_recovery_codes (user_id, code_hash) VALUES ($1, $2)',
          [row.user_id, hashRecoveryCode(recoveryCode)],
        );
      }
      await client.query(
        `UPDATE user_mfa_settings SET enabled = true, verified_at = now(),
          pending_setup_id = NULL, pending_secret_expires_at = NULL,
          recovery_codes_generated_at = now(), updated_at = now()
         WHERE user_id = $1`,
        [row.user_id],
      );
      await client.query(
        'UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND session_id <> $2 AND revoked_at IS NULL',
        [row.user_id, auth.sessionId],
      );
      await writeAudit(client, {
        clinicId: row.clinic_id,
        actingUserId: row.user_id,
        targetType: 'User',
        targetId: row.user_id,
        action: 'security.2fa_enabled',
        sessionId: auth.sessionId,
      });
      await client.query('COMMIT');
      return recoveryCodes;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async createLoginChallenge(client, user, request) {
    const token = issueOpaqueToken();
    await client.query(
      `INSERT INTO mfa_challenges
         (user_id, clinic_id, challenge_token_hash, device_name, platform, ip_address, user_agent, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,now() + ($8 || ' minutes')::interval)`,
      [
        user.user_id,
        user.clinic_id,
        token.hash,
        request.deviceName ?? null,
        request.platform ?? null,
        request.ipAddress ?? null,
        request.userAgent ?? null,
        challengeMinutes,
      ],
    );
    return { mfaRequired: true, challengeToken: token.raw, expiresIn: challengeMinutes * 60 };
  }

  async verifyLoginChallenge(challengeToken, code, recoveryCode, ipAddress) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query(
        `SELECT c.*, u.*, m.enabled, m.encrypted_totp_secret
           FROM mfa_challenges c
           JOIN users u ON u.user_id = c.user_id
           JOIN user_mfa_settings m ON m.user_id = u.user_id
          WHERE c.challenge_token_hash = $1 AND c.consumed_at IS NULL
            AND c.revoked_at IS NULL AND c.expires_at > now() FOR UPDATE`,
        [hashSecret(challengeToken)],
      )).rows[0];
      if (!row || row.failed_attempts >= maximumAttempts) throw new Error('The verification challenge is invalid or expired.');
      if (row.status !== 'Active') throw accountSuspendedError();
      const valid = recoveryCode
        ? await this.#consumeRecoveryCode(client, row.user_id, recoveryCode)
        : verifyTotp(code ?? '', decryptSecret(row.encrypted_totp_secret, this.environment.TOTP_ENCRYPTION_KEY));
      if (!valid) {
        await client.query(
          'UPDATE mfa_challenges SET failed_attempts = failed_attempts + 1 WHERE challenge_id = $1',
          [row.challenge_id],
        );
        await writeAudit(client, {
          clinicId: row.clinic_id,
          actingUserId: row.user_id,
          targetType: 'User',
          targetId: row.user_id,
          action: 'security.2fa_failed',
          ipAddress,
          success: false,
        });
        await client.query('COMMIT');
        const invalid = new Error('The verification code is invalid.');
        invalid.mfaFailureCommitted = true;
        throw invalid;
      }
      const access = await this.authService.completeMfaSignIn(client, row, {
        deviceName: row.device_name,
        platform: row.platform,
        ipAddress,
        userAgent: row.user_agent,
      });
      await client.query('UPDATE mfa_challenges SET consumed_at = now() WHERE challenge_id = $1', [row.challenge_id]);
      await client.query('COMMIT');
      return access;
    } catch (error) {
      if (!error.mfaFailureCommitted) await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async disable(auth, password, codeOrRecovery) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query(
        `SELECT u.*, m.encrypted_totp_secret FROM users u
         JOIN user_mfa_settings m ON m.user_id = u.user_id
         WHERE u.user_id = $1 AND m.enabled = true FOR UPDATE`,
        [auth.userId],
      )).rows[0];
      if (!row || !(await verifyPassword(password, row.password_hash))) throw new Error('Reauthentication failed.');
      const isTotp = /^\d{6}$/.test(codeOrRecovery);
      const valid = isTotp
        ? verifyTotp(codeOrRecovery, decryptSecret(row.encrypted_totp_secret, this.environment.TOTP_ENCRYPTION_KEY))
        : await this.#consumeRecoveryCode(client, row.user_id, codeOrRecovery);
      if (!valid) throw new Error('The verification code is invalid.');
      await client.query(
        `UPDATE user_mfa_settings SET enabled = false, encrypted_totp_secret = NULL,
          verified_at = NULL, updated_at = now() WHERE user_id = $1`,
        [row.user_id],
      );
      await client.query('DELETE FROM user_recovery_codes WHERE user_id = $1', [row.user_id]);
      await client.query(
        'UPDATE users SET token_version = token_version + 1, updated_at = now() WHERE user_id = $1',
        [row.user_id],
      );
      await client.query(
        'UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [row.user_id],
      );
      await client.query(
        'UPDATE mfa_challenges SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [row.user_id],
      );
      await writeAudit(client, {
        clinicId: row.clinic_id,
        actingUserId: row.user_id,
        targetType: 'User',
        targetId: row.user_id,
        action: 'security.2fa_disabled',
        sessionId: auth.sessionId,
      });
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async regenerateRecoveryCodes(auth, password, codeOrRecovery) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query(
        `SELECT u.*, m.encrypted_totp_secret FROM users u
         JOIN user_mfa_settings m ON m.user_id = u.user_id
         WHERE u.user_id = $1 AND u.status = 'Active' AND m.enabled = true
         FOR UPDATE`,
        [auth.userId],
      )).rows[0];
      if (!row || !(await verifyPassword(password, row.password_hash))) {
        throw new Error('Reauthentication failed.');
      }
      const isTotp = /^\d{6}$/.test(codeOrRecovery);
      const valid = isTotp
        ? verifyTotp(
            codeOrRecovery,
            decryptSecret(
              row.encrypted_totp_secret,
              this.environment.TOTP_ENCRYPTION_KEY,
            ),
          )
        : await this.#consumeRecoveryCode(
            client,
            row.user_id,
            codeOrRecovery,
          );
      if (!valid) throw new Error('The verification code is invalid.');

      const recoveryCodes = generateRecoveryCodes();
      await client.query(
        'DELETE FROM user_recovery_codes WHERE user_id = $1',
        [row.user_id],
      );
      for (const recoveryCode of recoveryCodes) {
        await client.query(
          'INSERT INTO user_recovery_codes (user_id, code_hash) VALUES ($1, $2)',
          [row.user_id, hashRecoveryCode(recoveryCode)],
        );
      }
      await client.query(
        `UPDATE user_mfa_settings
            SET recovery_codes_generated_at = now(), updated_at = now()
          WHERE user_id = $1`,
        [row.user_id],
      );
      await writeAudit(client, {
        clinicId: row.clinic_id,
        actingUserId: row.user_id,
        targetType: 'User',
        targetId: row.user_id,
        action: 'security.2fa_recovery_codes_regenerated',
        sessionId: auth.sessionId,
      });
      await client.query('COMMIT');
      return recoveryCodes;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async #consumeRecoveryCode(client, userId, value) {
    const normalized = normalizeRecoveryCode(value);
    if (!/^[A-F0-9]{16}$/.test(normalized)) return false;
    const result = await client.query(
      `UPDATE user_recovery_codes SET consumed_at = now()
        WHERE recovery_code_id = (
          SELECT recovery_code_id FROM user_recovery_codes
          WHERE user_id = $1 AND code_hash = $2 AND consumed_at IS NULL
          LIMIT 1 FOR UPDATE
        ) RETURNING recovery_code_id`,
      [userId, hashRecoveryCode(normalized)],
    );
    return result.rowCount === 1;
  }
}

function cryptoRandomUuid() {
  return globalThis.crypto.randomUUID();
}

function accountSuspendedError() {
  const error = new Error('Account access is restricted.');
  error.code = 'ACCOUNT_SUSPENDED';
  return error;
}
