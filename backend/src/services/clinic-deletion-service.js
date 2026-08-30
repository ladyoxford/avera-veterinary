import { randomInt, randomUUID } from 'node:crypto';
import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { hashToken } from '../security/tokens.js';

const deletionCodeTtlMinutes = 15;
const maximumCodeAttempts = 5;

export class ClinicDeletionService {
  constructor({ pool, deliveryService }) {
    this.pool = pool;
    this.deliveryService = deliveryService;
  }

  async requestDeletion(context) {
    const code = String(randomInt(100000, 1000000));
    const requestId = randomUUID();
    const expiresAt = new Date(Date.now() + deletionCodeTtlMinutes * 60 * 1000);
    const pending = await withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const clinic = (
          await client.query(
            `SELECT c.clinic_id, c.name, c.status,
                    COALESCE(
                      NULLIF(trim(a.administrator_email::text), ''),
                      NULLIF(trim(a.clinic_email::text), ''),
                      NULLIF(trim(c.email::text), '')
                    ) AS account_email
               FROM clinics c
               LEFT JOIN LATERAL (
                 SELECT administrator_email, clinic_email
                   FROM clinic_applications
                  WHERE clinic_id = c.clinic_id
                  ORDER BY submitted_at DESC
                  LIMIT 1
               ) a ON true
              WHERE c.clinic_id = $1 AND c.deleted_at IS NULL
              FOR UPDATE OF c`,
            [context.clinicId],
          )
        ).rows[0];
        if (!clinic) {
          throw serviceError('clinic_not_found', 'Clinic not found.', 404);
        }
        if (!clinic.account_email) {
          throw serviceError(
            'clinic_deletion_email_missing',
            'A canonical clinic Account Email is required before mutual deletion can begin.',
            409,
          );
        }
        await client.query(
          `UPDATE clinic_deletion_requests
              SET status = 'Cancelled', updated_at = now()
            WHERE clinic_id = $1 AND status = 'Pending'`,
          [context.clinicId],
        );
        await client.query(
          `INSERT INTO clinic_deletion_requests
             (request_id, clinic_id, requested_by, recipient_email,
              code_hash, status, attempts_remaining, reason, expires_at)
           VALUES ($1, $2, $3, $4, $5, 'Pending', $6, $7, $8)`,
          [
            requestId,
            context.clinicId,
            context.actorUserId,
            String(clinic.account_email).trim().toLowerCase(),
            deletionCodeHash(requestId, code),
            maximumCodeAttempts,
            context.reason ?? null,
            expiresAt,
          ],
        );
        await writeAudit(client, {
          clinicId: context.clinicId,
          actingUserId: context.actorUserId,
          targetType: 'Clinic',
          targetId: context.clinicId,
          action: 'clinic.mutual_deletion_requested',
          previousSummary: { status: clinic.status },
          newSummary: {
            deletionRequestId: requestId,
            recipientEmail: clinic.account_email,
            expiresAt,
          },
          sessionId: context.sessionId,
          ipAddress: context.ipAddress,
          reason: context.reason,
        });
        return {
          clinicId: clinic.clinic_id,
          clinicName: clinic.name,
          email: String(clinic.account_email).trim().toLowerCase(),
        };
      },
    );

    if (!this.deliveryService.configured) {
      await this.#markDeliveryFailed(requestId);
      throw serviceError(
        'clinic_deletion_email_unavailable',
        'Deletion confirmation email is not configured. No clinic data was deleted.',
        503,
      );
    }
    try {
      const delivery = await this.deliveryService.sendClinicDeletionCode({
        to: pending.email,
        clinicName: pending.clinicName,
        code,
        expiresAt,
        reason: context.reason,
        idempotencyKey: `clinic-deletion-${requestId}`,
      });
      await this.pool.query(
        `UPDATE clinic_deletion_requests
            SET delivered_at = now(), delivery_reference = $2,
                updated_at = now()
          WHERE request_id = $1 AND status = 'Pending'`,
        [requestId, delivery.reference],
      );
    } catch (_) {
      await this.#markDeliveryFailed(requestId);
      throw serviceError(
        'clinic_deletion_email_failed',
        'The deletion code could not be delivered. No clinic data was deleted.',
        502,
      );
    }

    return {
      requestId,
      clinicId: pending.clinicId,
      recipientEmail: maskEmail(pending.email),
      expiresAt,
      attemptsRemaining: maximumCodeAttempts,
      status: 'Pending',
    };
  }

  async confirmDeletion(context) {
    const result = await withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const request = (
          await client.query(
            `SELECT d.*, c.name AS clinic_name, c.status AS clinic_status
               FROM clinic_deletion_requests d
               JOIN clinics c ON c.clinic_id = d.clinic_id
              WHERE d.request_id = $1 AND d.clinic_id = $2
              FOR UPDATE OF d, c`,
            [context.requestId, context.clinicId],
          )
        ).rows[0];
        if (!request) {
          throw serviceError(
            'clinic_deletion_request_not_found',
            'The deletion request could not be found.',
            404,
          );
        }
        if (request.status !== 'Pending') {
          throw serviceError(
            'clinic_deletion_request_unavailable',
            'This deletion request is no longer available.',
            409,
          );
        }
        if (new Date(request.expires_at) <= new Date()) {
          await client.query(
            `UPDATE clinic_deletion_requests
                SET status = 'Expired', updated_at = now()
              WHERE request_id = $1`,
            [context.requestId],
          );
          return {
            failure: {
              code: 'clinic_deletion_code_expired',
              message: 'The deletion code has expired. Request a new code.',
              statusCode: 410,
            },
          };
        }
        if (request.attempts_remaining <= 0) {
          throw serviceError(
            'clinic_deletion_attempts_exhausted',
            'Too many incorrect deletion-code attempts. Request a new code.',
            429,
          );
        }
        if (
          request.code_hash !==
          deletionCodeHash(context.requestId, String(context.code).trim())
        ) {
          const remaining = request.attempts_remaining - 1;
          await client.query(
            `UPDATE clinic_deletion_requests
                SET attempts_remaining = $2,
                    status = CASE WHEN $2 = 0 THEN 'Cancelled' ELSE status END,
                    updated_at = now()
              WHERE request_id = $1`,
            [context.requestId, remaining],
          );
          await writeAudit(client, {
            clinicId: context.clinicId,
            actingUserId: context.actorUserId,
            targetType: 'Clinic',
            targetId: context.clinicId,
            action: 'clinic.mutual_deletion_code_rejected',
            newSummary: { attemptsRemaining: remaining },
            sessionId: context.sessionId,
            ipAddress: context.ipAddress,
            success: false,
          });
          return {
            failure: {
              code: 'clinic_deletion_code_invalid',
              message: remaining > 0
                ? `The deletion code is incorrect. ${remaining} attempt(s) remain.`
                : 'The deletion code is incorrect and this request has been cancelled.',
              statusCode: 400,
            },
          };
        }

        const deletedAt = new Date();
        const tombstoneDomain = 'deleted.averavet.invalid';
        await client.query(
          `UPDATE sessions
              SET revoked_at = COALESCE(revoked_at, now())
            WHERE user_id IN (
              SELECT user_id FROM users WHERE clinic_id = $1
            )`,
          [context.clinicId],
        );
        await client.query(
          `UPDATE activation_tokens
              SET revoked_at = COALESCE(revoked_at, now())
            WHERE clinic_id = $1 AND used_at IS NULL`,
          [context.clinicId],
        );
        await client.query(
          `UPDATE clinic_memberships
              SET membership_status = 'Deactivated', deleted_at = now(),
                  updated_at = now(), updated_by = $2,
                  revision = revision + 1
            WHERE clinic_id = $1 AND deleted_at IS NULL`,
          [context.clinicId, context.actorUserId],
        );
        await client.query(
          `UPDATE users
              SET email = concat('deleted+', user_id::text, '@${tombstoneDomain}'),
                  status = 'Deactivated', deleted_at = now(),
                  token_version = token_version + 1,
                  updated_at = now(), updated_by = $2,
                  revision = revision + 1
            WHERE clinic_id = $1 AND deleted_at IS NULL`,
          [context.clinicId, context.actorUserId],
        );
        await client.query(
          `UPDATE clinic_applications
              SET status = 'Deleted',
                  administrator_email = concat(
                    'deleted+', application_id::text, '@${tombstoneDomain}'
                  ),
                  clinic_email = concat(
                    'deleted+', application_id::text, '@${tombstoneDomain}'
                  ),
                  updated_at = now()
            WHERE clinic_id = $1`,
          [context.clinicId],
        );
        await client.query(
          `UPDATE subscriptions
              SET status = 'Cancelled', cancelled_at = COALESCE(cancelled_at, now()),
                  updated_at = now()
            WHERE clinic_id = $1
              AND status NOT IN ('Cancelled', 'Expired')`,
          [context.clinicId],
        );
        await client.query(
          `UPDATE clinics
              SET email = concat(
                    'deleted+', clinic_id::text, '@${tombstoneDomain}'
                  ),
                  status = 'Archived', deleted_at = now(),
                  updated_at = now(), updated_by = $2,
                  revision = revision + 1
            WHERE clinic_id = $1 AND deleted_at IS NULL`,
          [context.clinicId, context.actorUserId],
        );
        await client.query(
          `UPDATE clinic_deletion_requests
              SET status = 'Confirmed', confirmed_at = now(),
                  confirmed_by = $2, updated_at = now()
            WHERE request_id = $1`,
          [context.requestId, context.actorUserId],
        );
        await writeAudit(client, {
          clinicId: context.clinicId,
          actingUserId: context.actorUserId,
          targetType: 'Clinic',
          targetId: context.clinicId,
          action: 'clinic.mutual_deletion_confirmed',
          previousSummary: {
            status: request.clinic_status,
            accountEmail: request.recipient_email,
          },
          newSummary: {
            status: 'Archived',
            deletedAt,
            registrationEmailReleased: true,
          },
          sessionId: context.sessionId,
          ipAddress: context.ipAddress,
          reason: request.reason,
        });
        return {
          clinicId: context.clinicId,
          clinicName: request.clinic_name,
          status: 'Deleted',
          deletedAt,
          registrationEmailReleased: true,
        };
      },
    );
    if (result.failure) {
      throw serviceError(
        result.failure.code,
        result.failure.message,
        result.failure.statusCode,
      );
    }
    return result;
  }

  async #markDeliveryFailed(requestId) {
    await this.pool.query(
      `UPDATE clinic_deletion_requests
          SET status = 'DeliveryFailed', updated_at = now()
        WHERE request_id = $1 AND status = 'Pending'`,
      [requestId],
    );
  }
}

function deletionCodeHash(requestId, code) {
  return hashToken(`${requestId}:${code}`);
}

function maskEmail(email) {
  const [local, domain] = String(email).split('@');
  if (!domain) return 'the clinic Account Email';
  const visible = local.slice(0, Math.min(2, local.length));
  return `${visible}${'*'.repeat(Math.max(3, local.length - visible.length))}@${domain}`;
}

function serviceError(code, message, statusCode) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}
