import { randomBytes } from 'node:crypto';
import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { hashPassword, validatePassword } from '../security/passwords.js';
import { hashToken } from '../security/tokens.js';
import { clinicAdministratorPermissionKeys } from '../security/permission-catalog.js';

const purpose = 'ClinicAdministratorActivation';
const clinicAdministratorPermissions = new Set(
  clinicAdministratorPermissionKeys,
);

export class ClinicAdministratorActivationService {
  constructor({ pool, environment, deliveryService }) {
    this.pool = pool;
    this.environment = environment;
    this.deliveryService = deliveryService;
  }

  async provisionOnApproval(client, context) {
    const application = (
      await client.query(
        `SELECT * FROM clinic_applications
          WHERE clinic_id = $1
          ORDER BY submitted_at DESC
          LIMIT 1 FOR UPDATE`,
        [context.clinicId],
      )
    ).rows[0];
    if (!application?.administrator_email || !application?.administrator_name) {
      throw serviceError(
        'administrator_details_missing',
        'The clinic application does not contain administrator details.',
        409,
      );
    }

    const role = (
      await client.query(
        `INSERT INTO roles
           (clinic_id, name, description, is_system_role, created_by, updated_by)
         VALUES
           ($1, 'Clinic Administrator',
            'Full clinic administration and operational access.', true, $2, $2)
         ON CONFLICT (clinic_id, name) DO UPDATE
           SET description = EXCLUDED.description,
               is_system_role = true,
               updated_at = now(), updated_by = EXCLUDED.updated_by,
               deleted_at = NULL
         RETURNING role_id`,
        [context.clinicId, context.actorUserId],
      )
    ).rows[0];
    const permissionRows = await client.query(
      'SELECT permission_id, permission_key FROM permissions',
    );
    const clinicPermissionIds = permissionRows.rows
      .filter((row) => clinicAdministratorPermissions.has(row.permission_key))
      .map((row) => row.permission_id);
    if (clinicPermissionIds.length > 0) {
      await client.query(
        `INSERT INTO role_permissions (role_id, permission_id)
         SELECT $1, unnest($2::uuid[])
         ON CONFLICT DO NOTHING`,
        [role.role_id, clinicPermissionIds],
      );
    }

    const normalizedEmail = String(application.administrator_email).toLowerCase();
    let user = (
      await client.query(
        'SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL FOR UPDATE',
        [normalizedEmail],
      )
    ).rows[0];
    if (user && (
      user.account_type !== 'ClinicAdministrator' ||
      user.clinic_id !== context.clinicId
    )) {
      throw serviceError(
        'administrator_identity_conflict',
        'This email already belongs to another AVERA account.',
        409,
      );
    }
    if (!user) {
      user = (
        await client.query(
          `INSERT INTO users
             (clinic_id, full_name, email, phone, password_hash,
              account_type, status, role_id, created_by, updated_by)
           VALUES ($1, $2, $3, $4, NULL,
                   'ClinicAdministrator', 'PendingActivation', $5, $6, $6)
           RETURNING *`,
          [
            context.clinicId,
            application.administrator_name,
            normalizedEmail,
            application.administrator_phone,
            role.role_id,
            context.actorUserId,
          ],
        )
      ).rows[0];
    } else if (user.status !== 'Active') {
      user = (
        await client.query(
          `UPDATE users
              SET full_name = $2, phone = $3, role_id = $4,
                  status = 'PendingActivation', updated_at = now(),
                  updated_by = $5, deleted_at = NULL
            WHERE user_id = $1
            RETURNING *`,
          [
            user.user_id,
            application.administrator_name,
            application.administrator_phone,
            role.role_id,
            context.actorUserId,
          ],
        )
      ).rows[0];
    }

    await client.query(
      `INSERT INTO clinic_memberships
         (user_id, clinic_id, role_id, membership_status, invited_at,
          created_by, updated_by)
       VALUES ($1, $2, $3, $4, now(), $5, $5)
       ON CONFLICT (user_id, clinic_id) DO UPDATE
         SET role_id = EXCLUDED.role_id,
             membership_status = CASE
               WHEN clinic_memberships.membership_status = 'Active'
                 THEN 'Active'::membership_status
               ELSE 'Invited'::membership_status
             END,
             updated_at = now(), updated_by = EXCLUDED.updated_by,
             deleted_at = NULL`,
      [
        user.user_id,
        context.clinicId,
        role.role_id,
        user.status === 'Active' ? 'Active' : 'Invited',
        context.actorUserId,
      ],
    );
    await client.query(
      `UPDATE clinic_applications
          SET applicant_user_id = $2, status = 'Approved', reviewed_at = now(),
              reviewed_by = $3, updated_at = now()
        WHERE application_id = $1`,
      [application.application_id, user.user_id, context.actorUserId],
    );

    let issued = null;
    if (user.status !== 'Active') {
      issued = await this.#issueToken(client, {
        clinicId: context.clinicId,
        user,
        clinicName: context.clinicName,
        actorUserId: context.actorUserId,
        ipAddress: context.ipAddress,
        force: false,
      });
    }
    await writeAudit(client, {
      clinicId: context.clinicId,
      actingUserId: context.actorUserId,
      targetType: 'User',
      targetId: user.user_id,
      action: 'administrator.provisioned_for_activation',
      newSummary: {
        email: normalizedEmail,
        status: user.status,
        tokenIssued: issued != null,
      },
      sessionId: context.sessionId,
      ipAddress: context.ipAddress,
    });
    return { user, issued };
  }

  async deliverIssuedToken(issued) {
    if (!issued) return null;
    const activationUrl = this.#activationUrl(issued.rawToken);
    if (!this.deliveryService.configured) {
      return {
        status: 'PendingActivation',
        email: issued.email,
        expiresAt: issued.expiresAt,
        deliveryMethod: 'manual',
        activationUrl,
      };
    }
    try {
      const delivery = await this.deliveryService.sendClinicAdministratorActivation({
        to: issued.email,
        applicantName: issued.fullName,
        clinicName: issued.clinicName,
        activationUrl,
        expiresAt: issued.expiresAt,
        idempotencyKey: `activation-${issued.tokenId}`,
      });
      await this.pool.query(
        `UPDATE activation_tokens
            SET delivery_method = 'email', delivered_at = now(),
                delivery_reference = $2
          WHERE token_id = $1`,
        [issued.tokenId, delivery.reference],
      );
      return {
        status: 'PendingActivation',
        email: issued.email,
        expiresAt: issued.expiresAt,
        deliveryMethod: 'email',
      };
    } catch (_) {
      await this.pool.query(
        `UPDATE activation_tokens
            SET delivery_method = 'email_failed'
          WHERE token_id = $1`,
        [issued.tokenId],
      );
      return {
        status: 'DeliveryFailed',
        email: issued.email,
        expiresAt: issued.expiresAt,
        deliveryMethod: 'email_failed',
      };
    }
  }

  async activationStatus(clinicId) {
    return withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const result = await client.query(
      `SELECT u.user_id, u.full_name, u.email, u.status,
              t.expires_at, t.used_at, t.revoked_at, t.delivery_method,
              t.delivered_at
         FROM users u
         LEFT JOIN LATERAL (
           SELECT expires_at, used_at, revoked_at, delivery_method, delivered_at
             FROM activation_tokens
            WHERE user_id = u.user_id AND purpose = $2
            ORDER BY created_at DESC LIMIT 1
         ) t ON true
        WHERE u.clinic_id = $1
          AND u.account_type = 'ClinicAdministrator'
          AND u.deleted_at IS NULL
        ORDER BY u.created_at
        LIMIT 1`,
      [clinicId, purpose],
    );
        const row = result.rows[0];
        if (!row) return { status: 'NotProvisioned', canResend: false };
        return mapActivationStatus(row);
      },
    );
  }

  async resend(context) {
    const issued = await withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const clinic = (
          await client.query(
            `SELECT clinic_id, name, status FROM clinics
              WHERE clinic_id = $1 AND deleted_at IS NULL FOR UPDATE`,
            [context.clinicId],
          )
        ).rows[0];
        if (!clinic || clinic.status !== 'Active') {
          throw serviceError(
            'clinic_not_approved',
            'The clinic must be approved before activation can be resent.',
            409,
          );
        }
        const user = (
          await client.query(
            `SELECT * FROM users
              WHERE clinic_id = $1 AND account_type = 'ClinicAdministrator'
                AND deleted_at IS NULL
              ORDER BY created_at LIMIT 1 FOR UPDATE`,
            [context.clinicId],
          )
        ).rows[0];
        if (!user || user.status === 'Active') {
          throw serviceError(
            'activation_not_required',
            'This clinic administrator is already active or has not been provisioned.',
            409,
          );
        }
        const token = await this.#issueToken(client, {
          clinicId: context.clinicId,
          user,
          clinicName: clinic.name,
          actorUserId: context.actorUserId,
          ipAddress: context.ipAddress,
          force: true,
        });
        await writeAudit(client, {
          clinicId: context.clinicId,
          actingUserId: context.actorUserId,
          targetType: 'User',
          targetId: user.user_id,
          action: 'administrator.activation_resent',
          newSummary: { expiresAt: token.expiresAt },
          sessionId: context.sessionId,
          ipAddress: context.ipAddress,
        });
        return token;
      },
    );
    return this.deliverIssuedToken(issued);
  }

  async inspect(rawToken) {
    return withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const row = await this.#tokenRecord(rawToken, false, client);
        this.#assertUsable(row);
        return {
          clinicName: row.clinic_name,
          administratorName: row.full_name,
          email: row.email,
          expiresAt: row.expires_at,
        };
      },
    );
  }

  async activate({ rawToken, password, confirmPassword, ipAddress }) {
    if (password !== confirmPassword) {
      throw serviceError('password_mismatch', 'Passwords do not match.', 400);
    }
    const passwordError = validatePassword(password);
    if (passwordError) {
      throw serviceError('weak_password', passwordError, 400);
    }
    return withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const row = await this.#tokenRecord(rawToken, true, client);
        this.#assertUsable(row);
        const passwordHash = await hashPassword(password);
        const now = new Date();
        await client.query(
          `UPDATE users
              SET password_hash = $2, status = 'Active',
                  requires_password_change = false,
                  email_verified_at = COALESCE(email_verified_at, $3),
                  failed_login_count = 0, locked_until = NULL,
                  updated_at = $3, revision = revision + 1
            WHERE user_id = $1`,
          [row.user_id, passwordHash, now],
        );
        await client.query(
          `UPDATE clinic_memberships
              SET membership_status = 'Active', activated_at = $2,
                  updated_at = $2, revision = revision + 1
            WHERE user_id = $1 AND clinic_id = $3 AND deleted_at IS NULL`,
          [row.user_id, now, row.clinic_id],
        );
        await client.query(
          `UPDATE activation_tokens
              SET used_at = CASE WHEN token_id = $2 THEN $3 ELSE used_at END,
                  revoked_at = CASE
                    WHEN token_id <> $2 AND used_at IS NULL THEN $3
                    ELSE revoked_at
                  END
            WHERE user_id = $1 AND purpose = $4`,
          [row.user_id, row.token_id, now, purpose],
        );
        await client.query(
          `UPDATE sessions SET revoked_at = now()
            WHERE user_id = $1 AND revoked_at IS NULL`,
          [row.user_id],
        );
        await writeAudit(client, {
          clinicId: row.clinic_id,
          actingUserId: row.user_id,
          targetType: 'User',
          targetId: row.user_id,
          action: 'administrator.activated',
          previousSummary: { status: 'PendingActivation' },
          newSummary: { status: 'Active' },
          ipAddress,
        });
        return {
          activated: true,
          email: row.email,
          mfaEnrollmentRecommended: true,
        };
      },
    );
  }

  async #issueToken(client, context) {
    const now = new Date();
    const existing = (
      await client.query(
        `SELECT token_id, expires_at FROM activation_tokens
          WHERE user_id = $1 AND purpose = $2
            AND used_at IS NULL AND revoked_at IS NULL
          ORDER BY created_at DESC LIMIT 1 FOR UPDATE`,
        [context.user.user_id, purpose],
      )
    ).rows[0];
    if (existing && !context.force && existing.expires_at > now) return null;
    await client.query(
      `UPDATE activation_tokens SET revoked_at = $3
        WHERE user_id = $1 AND purpose = $2
          AND used_at IS NULL AND revoked_at IS NULL`,
      [context.user.user_id, purpose, now],
    );
    const rawToken = randomBytes(32).toString('base64url');
    const expiresAt = new Date(
      now.getTime() + this.environment.ACTIVATION_TOKEN_TTL_MINUTES * 60_000,
    );
    const inserted = (
      await client.query(
        `INSERT INTO activation_tokens
           (user_id, clinic_id, purpose, token_hash, expires_at,
            requested_from_ip, metadata)
         VALUES ($1, $2, $3, $4, $5, $6,
                 jsonb_build_object('issuedBy', $7::text))
         RETURNING token_id`,
        [
          context.user.user_id,
          context.clinicId,
          purpose,
          hashToken(rawToken),
          expiresAt,
          context.ipAddress ?? null,
          context.actorUserId,
        ],
      )
    ).rows[0];
    return {
      tokenId: inserted.token_id,
      rawToken,
      expiresAt,
      email: context.user.email,
      fullName: context.user.full_name,
      clinicName: context.clinicName,
    };
  }

  async #tokenRecord(rawToken, forUpdate, providedClient) {
    const client = providedClient ?? this.pool;
    const result = await client.query(
      `SELECT t.*, u.full_name, u.email, u.status AS user_status,
              c.name AS clinic_name, c.status AS clinic_status
         FROM activation_tokens t
         JOIN users u ON u.user_id = t.user_id
         JOIN clinics c ON c.clinic_id = t.clinic_id
        WHERE t.token_hash = $1 AND t.purpose = $2
        ${forUpdate ? 'FOR UPDATE OF t, u' : ''}`,
      [hashToken(rawToken), purpose],
    );
    return result.rows[0];
  }

  #assertUsable(row) {
    if (!row) {
      throw serviceError('activation_invalid', 'This activation link is invalid.', 400);
    }
    if (row.used_at) {
      throw serviceError('activation_used', 'This activation link has already been used.', 409);
    }
    if (row.revoked_at) {
      throw serviceError('activation_revoked', 'This activation link is no longer valid.', 409);
    }
    if (new Date(row.expires_at) <= new Date()) {
      throw serviceError('activation_expired', 'This activation link has expired.', 410);
    }
    if (row.user_status !== 'PendingActivation' || row.clinic_status !== 'Active') {
      throw serviceError(
        'activation_unavailable',
        'This account is not available for activation.',
        409,
      );
    }
  }

  #activationUrl(rawToken) {
    const url = new URL(this.environment.AVERA_ACTIVATION_BASE_URL);
    url.searchParams.set('token', rawToken);
    return url.toString();
  }
}

export class ActivationEmailDeliveryService {
  constructor({ environment, fetchImpl = globalThis.fetch }) {
    this.environment = environment;
    this.fetchImpl = fetchImpl;
  }

  get configured() {
    return Boolean(
      this.environment.RESEND_API_KEY &&
      this.environment.ACTIVATION_EMAIL_FROM,
    );
  }

  async sendClinicAdministratorActivation(message) {
    if (!this.configured) throw new Error('Activation email is not configured.');
    const response = await this.fetchImpl('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.environment.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
        'User-Agent': 'AVERA-Backend/1.0',
        'Idempotency-Key': message.idempotencyKey,
      },
      body: JSON.stringify({
        from: this.environment.ACTIVATION_EMAIL_FROM,
        to: [message.to],
        subject: `Activate your ${message.clinicName} administrator account`,
        text: activationEmailText(message),
      }),
    });
    if (!response.ok) throw new Error('Activation email delivery failed.');
    const body = await response.json();
    return { reference: body.id ?? null };
  }
}

function activationEmailText(message) {
  return [
    `Hello ${message.applicantName},`,
    '',
    `${message.clinicName} has been approved on AVERA.`,
    'Create your Clinic Administrator password using this single-use link:',
    message.activationUrl,
    '',
    `This link expires at ${new Date(message.expiresAt).toISOString()}.`,
    'If you did not submit this clinic application, contact AVERA support.',
  ].join('\n');
}

function mapActivationStatus(row) {
  let status = row.status;
  if (row.status === 'PendingActivation') {
    if (row.used_at) status = 'Active';
    else if (row.revoked_at) status = 'LinkRevoked';
    else if (row.expires_at && new Date(row.expires_at) <= new Date()) {
      status = 'LinkExpired';
    }
  }
  return {
    status,
    administratorName: row.full_name,
    email: row.email,
    expiresAt: row.expires_at,
    deliveredAt: row.delivered_at,
    deliveryMethod: row.delivery_method,
    canResend: row.status === 'PendingActivation',
  };
}

function serviceError(code, message, statusCode) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}
