import { randomBytes } from 'node:crypto';

import { writeAudit } from '../audit/audit-service.js';
import { hashPassword, validatePassword } from '../security/passwords.js';
import { hashToken } from '../security/tokens.js';

const purpose = 'PasswordReset';

export class PasswordResetService {
  constructor({ pool, environment, deliveryService, logger = null }) {
    this.pool = pool;
    this.environment = environment;
    this.deliveryService = deliveryService;
    this.logger = logger;
  }

  async request({ email, ipAddress, userAgent }) {
    if (!this.deliveryService.configured) {
      throw serviceError(
        'email_delivery_unavailable',
        'Password recovery email is not configured.',
        503,
      );
    }

    const normalizedEmail = String(email).trim().toLowerCase();
    const client = await this.pool.connect();
    let issued = null;
    try {
      await client.query('BEGIN');
      const user = (
        await client.query(
          `SELECT user_id, clinic_id, full_name, email, status, password_hash
             FROM users
            WHERE email = $1 AND deleted_at IS NULL
            FOR UPDATE`,
          [normalizedEmail],
        )
      ).rows[0];
      if (user && user.password_hash && ['Active', 'Locked'].includes(user.status)) {
        const now = new Date();
        const expiresAt = new Date(
          now.getTime() +
            Number(this.environment.PASSWORD_RESET_TOKEN_TTL_MINUTES ?? 30) *
              60_000,
        );
        const rawToken = randomBytes(32).toString('base64url');
        await client.query(
          `UPDATE activation_tokens
              SET revoked_at = $2
            WHERE user_id = $1 AND purpose = $3
              AND used_at IS NULL AND revoked_at IS NULL`,
          [user.user_id, now, purpose],
        );
        const token = (
          await client.query(
            `INSERT INTO activation_tokens
               (user_id, clinic_id, purpose, token_hash, expires_at,
                requested_from_ip, requested_from_device, metadata)
             VALUES ($1, $2, $3, $4, $5, $6, $7,
                     jsonb_build_object('channel', 'email'))
             RETURNING token_id`,
            [
              user.user_id,
              user.clinic_id,
              purpose,
              hashToken(rawToken),
              expiresAt,
              ipAddress ?? null,
              userAgent ?? null,
            ],
          )
        ).rows[0];
        await writeAudit(client, {
          clinicId: user.clinic_id,
          actingUserId: null,
          targetType: 'User',
          targetId: user.user_id,
          action: 'password.reset_requested',
          newSummary: { channel: 'email', expiresAt },
          ipAddress,
        });
        issued = {
          tokenId: token.token_id,
          userId: user.user_id,
          clinicId: user.clinic_id,
          fullName: user.full_name,
          email: user.email,
          rawToken,
          expiresAt,
          ipAddress,
        };
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }

    if (issued) await this.#deliver(issued);
    return { accepted: true };
  }

  async reset({ rawToken, password, confirmPassword, ipAddress }) {
    if (password !== confirmPassword) {
      throw serviceError(
        'password_confirmation_mismatch',
        'The password confirmation does not match.',
        400,
      );
    }
    const passwordIssue = validatePassword(password);
    if (passwordIssue) {
      throw serviceError('password_policy_failed', passwordIssue, 400);
    }

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (
        await client.query(
          `SELECT t.token_id, t.user_id, t.clinic_id, t.expires_at,
                  t.used_at, t.revoked_at, u.email, u.status
             FROM activation_tokens t
             JOIN users u ON u.user_id = t.user_id
            WHERE t.token_hash = $1 AND t.purpose = $2
              AND u.deleted_at IS NULL
            FOR UPDATE OF t, u`,
          [hashToken(rawToken), purpose],
        )
      ).rows[0];
      if (
        !row ||
        row.used_at ||
        row.revoked_at ||
        new Date(row.expires_at) <= new Date() ||
        !['Active', 'Locked'].includes(row.status)
      ) {
        throw serviceError(
          'password_reset_invalid',
          'This password reset link is invalid, expired, or already used.',
          400,
        );
      }
      const now = new Date();
      await client.query(
        `UPDATE users
            SET password_hash = $2,
                status = CASE WHEN status = 'Locked' THEN 'Active' ELSE status END,
                failed_login_count = 0, locked_until = NULL,
                requires_password_change = false, updated_at = $3
          WHERE user_id = $1`,
        [row.user_id, await hashPassword(password), now],
      );
      await client.query(
        `UPDATE activation_tokens
            SET used_at = $2
          WHERE token_id = $1`,
        [row.token_id, now],
      );
      await client.query(
        `UPDATE activation_tokens
            SET revoked_at = $2
          WHERE user_id = $1 AND purpose = $3
            AND token_id <> $4 AND used_at IS NULL AND revoked_at IS NULL`,
        [row.user_id, now, purpose, row.token_id],
      );
      await client.query(
        `UPDATE sessions SET revoked_at = $2
          WHERE user_id = $1 AND revoked_at IS NULL`,
        [row.user_id, now],
      );
      await writeAudit(client, {
        clinicId: row.clinic_id,
        actingUserId: row.user_id,
        targetType: 'User',
        targetId: row.user_id,
        action: 'password.reset_completed',
        newSummary: { sessionsRevoked: true },
        ipAddress,
      });
      await client.query('COMMIT');
      return { reset: true, email: row.email };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async #deliver(issued) {
    let delivery;
    try {
      delivery = await this.deliveryService.sendPasswordReset({
        to: issued.email,
        fullName: issued.fullName,
        resetUrl: passwordResetUrl(
          this.environment.AVERA_PASSWORD_RESET_BASE_URL,
          issued.rawToken,
        ),
        expiresAt: issued.expiresAt,
        idempotencyKey: `password-reset-${issued.tokenId}`,
      });
    } catch (_) {
      delivery = {
        accepted: false,
        provider: this.deliveryService.provider,
        failureCode: 'email_provider_exception',
      };
    }
    const providerMessageId = typeof delivery?.providerMessageId === 'string'
      ? delivery.providerMessageId.trim()
      : '';
    const accepted = delivery?.accepted === true && providerMessageId.length > 0;
    const submittedAt = accepted
      ? delivery.submittedAt ?? new Date().toISOString()
      : null;
    let client;
    let transactionOpen = false;
    let bookkeepingStage = 'connect';
    try {
      client = await this.pool.connect();
      bookkeepingStage = 'begin';
      await client.query('BEGIN');
      transactionOpen = true;
      bookkeepingStage = 'delivery_metadata';
      await client.query(
        `UPDATE activation_tokens
            SET delivery_method = $2, delivered_at = $3,
                delivery_reference = $4,
                metadata = metadata || jsonb_build_object(
                  'emailProvider', $5::text,
                  'emailFailureCode', $6::text
                )
          WHERE token_id = $1`,
        [
          issued.tokenId,
          accepted ? 'email_submitted' : 'email_failed',
          submittedAt,
          accepted ? providerMessageId : null,
          delivery?.provider ?? null,
          accepted ? null : delivery?.failureCode ?? 'email_provider_invalid_result',
        ],
      );
      bookkeepingStage = 'audit';
      await writeAudit(client, {
        clinicId: issued.clinicId,
        actingUserId: null,
        targetType: 'User',
        targetId: issued.userId,
        action: accepted
          ? 'password.reset_email_submitted'
          : 'password.reset_email_submission_failed',
        newSummary: {
          provider: delivery?.provider ?? null,
          providerMessageId: accepted ? providerMessageId : null,
          failureCategory: accepted ? null : delivery?.failureCode ?? null,
        },
        ipAddress: issued.ipAddress,
        success: accepted,
      });
      bookkeepingStage = 'commit';
      await client.query('COMMIT');
      transactionOpen = false;
    } catch (error) {
      if (transactionOpen && client) {
        try {
          await client.query('ROLLBACK');
        } catch (rollbackError) {
          this.#logBookkeepingFailure(rollbackError, {
            accepted,
            provider: delivery?.provider ?? null,
            stage: 'rollback',
          });
        }
      }
      this.#logBookkeepingFailure(error, {
        accepted,
        provider: delivery?.provider ?? null,
        stage: bookkeepingStage,
      });
    } finally {
      if (client) {
        try {
          client.release();
        } catch (error) {
          this.#logBookkeepingFailure(error, {
            accepted,
            provider: delivery?.provider ?? null,
            stage: 'release',
          });
        }
      }
    }

    if (!accepted) {
      throw serviceError(
        'password_reset_delivery_failed',
        'The password reset email could not be sent. Please try again.',
        503,
      );
    }
  }

  #logBookkeepingFailure(error, { accepted, provider, stage }) {
    try {
      this.logger?.error?.(
        {
          event: 'password_reset_delivery_bookkeeping_failed',
          providerAccepted: accepted,
          provider,
          stage,
          errorName: error?.name ?? 'Error',
          errorCode: error?.code ?? null,
        },
        'Password reset delivery bookkeeping failed',
      );
    } catch (_) {
      // Logging must never change the user-facing delivery result.
    }
  }
}

export function passwordResetUrl(baseUrl, rawToken) {
  const url = new URL(baseUrl);
  url.searchParams.set('token', rawToken);
  return url.toString();
}

function serviceError(code, message, statusCode) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}
