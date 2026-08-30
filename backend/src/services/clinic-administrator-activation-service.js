import { randomBytes } from 'node:crypto';
import { writeAudit } from '../audit/audit-service.js';
import { withTenantTransaction } from '../database/pool.js';
import { hashPassword, validatePassword } from '../security/passwords.js';
import { hashToken } from '../security/tokens.js';
import { clinicAdministratorPermissionKeys } from '../security/permission-catalog.js';
import { ensureDefaultClinicRoles } from '../security/default-clinic-roles.js';
import { allocateClinicStaffNumber } from '../security/staff-number.js';

const purpose = 'ClinicAdministratorActivation';
const staffPurpose = 'StaffInvitation';
const clinicAdministratorPermissions = new Set(
  clinicAdministratorPermissionKeys,
);

export class ClinicAdministratorActivationService {
  constructor({ pool, environment, deliveryService }) {
    this.pool = pool;
    this.environment = environment;
    this.deliveryService = deliveryService;
  }

  async approveAfterVerifiedPayment(context) {
    const result = await withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
          `clinic-payment-approval:${context.applicationId}`,
        ]);
        const target = (
          await client.query(
            `SELECT a.application_id, a.clinic_id, a.status AS application_status,
                    a.payment_status, a.payment_reference, c.name AS clinic_name,
                    c.status AS clinic_status, p.status AS transaction_status
               FROM clinic_applications a
               JOIN clinics c ON c.clinic_id = a.clinic_id
               JOIN subscription_payment_transactions p
                 ON p.reference = a.payment_reference
                AND p.clinic_id = a.clinic_id
              WHERE a.application_id = $1 AND a.clinic_id = $2
              FOR UPDATE OF a, c, p`,
            [context.applicationId, context.clinicId],
          )
        ).rows[0];
        if (!target) {
          throw serviceError(
            'clinic_application_not_found',
            'The paid clinic application could not be found.',
            404,
          );
        }
        if (
          target.payment_reference !== context.reference ||
          target.transaction_status !== 'Successful' ||
          !['Paid', 'TestVerified'].includes(target.payment_status)
        ) {
          throw serviceError(
            'payment_not_verified',
            'The clinic application payment has not been verified.',
            409,
          );
        }

        const alreadyApproved =
          target.clinic_status === 'Active' &&
          target.application_status === 'Approved';
        if (
          !alreadyApproved &&
          (
            !['Pending', 'PendingApproval'].includes(target.clinic_status) ||
            !['Pending', 'PendingApproval'].includes(target.application_status)
          )
        ) {
          throw serviceError(
            'automatic_approval_not_allowed',
            'This clinic requires Platform Owner review before its status can change.',
            409,
          );
        }

        if (!alreadyApproved) {
          await client.query(
            `UPDATE clinics
                SET status = 'Active', updated_at = now(), revision = revision + 1
              WHERE clinic_id = $1`,
            [context.clinicId],
          );
        }
        const administrator = await this.provisionOnApproval(client, {
          clinicId: context.clinicId,
          clinicName: target.clinic_name,
          actorUserId: null,
          sessionId: null,
          ipAddress: context.ipAddress,
        });
        await writeAudit(client, {
          clinicId: context.clinicId,
          actingUserId: null,
          targetType: 'Clinic',
          targetId: context.clinicId,
          action: alreadyApproved
            ? 'clinic.administrator_reconciled_after_verified_payment'
            : 'clinic.auto_approved_after_verified_payment',
          previousSummary: {
            clinicStatus: target.clinic_status,
            applicationStatus: target.application_status,
          },
          newSummary: {
            clinicStatus: 'Active',
            applicationStatus: 'Approved',
            paymentStatus: target.payment_status,
            paymentReference: context.reference,
          },
          ipAddress: context.ipAddress,
        });
        return { approved: true, issued: administrator.issued };
      },
    );
    const activation = result.issued
      ? await this.deliverIssuedToken(result.issued)
      : await this.activationStatus(context.clinicId);
    return { approved: result.approved, activation };
  }

  async provisionOnApproval(client, context) {
    const application = (
      await client.query(
        `SELECT a.*,
                COALESCE(
                  NULLIF(trim(a.administrator_email::text), ''),
                  NULLIF(trim(a.clinic_email::text), ''),
                  NULLIF(trim(c.email::text), '')
                ) AS account_email
           FROM clinic_applications a
           JOIN clinics c ON c.clinic_id = a.clinic_id
          WHERE a.clinic_id = $1
          ORDER BY a.submitted_at DESC
          LIMIT 1 FOR UPDATE OF a`,
        [context.clinicId],
      )
    ).rows[0];
    const accountEmail =
      application?.account_email ??
      application?.administrator_email ??
      application?.clinic_email;
    if (!accountEmail) {
      throw serviceError(
        'administrator_account_email_missing',
        'The Clinic Administrator could not be provisioned because no valid registration Account Email is available.',
        409,
      );
    }
    if (!application?.administrator_name) {
      throw serviceError(
        'administrator_name_missing',
        'The Clinic Administrator could not be provisioned because the clinic application has no administrator name.',
        409,
      );
    }

    const role = (
      await client.query(
        `INSERT INTO roles
           (clinic_id, code, name, description, is_system_role, created_by, updated_by)
         VALUES
           ($1, 'clinic_administrator', 'Clinic Administrator',
            'Full clinic administration and operational access.', true, $2, $2)
         ON CONFLICT (clinic_id, name) DO UPDATE
           SET code = EXCLUDED.code,
               description = EXCLUDED.description,
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
    await ensureDefaultClinicRoles(client, {
      clinicId: context.clinicId,
      actorUserId: context.actorUserId,
    });

    const normalizedEmail = String(accountEmail).trim().toLowerCase();
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
    } else {
      user = (
        await client.query(
          `UPDATE users
              SET full_name = $2, phone = $3, role_id = $4,
                  updated_at = now(), updated_by = $5, deleted_at = NULL
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
               SELECT expires_at, used_at, revoked_at, delivery_method,
                      delivered_at
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
        if (!row) {
          const repair = (
            await client.query(
              `SELECT c.status AS clinic_status,
                      a.administrator_name,
                      COALESCE(
                        NULLIF(trim(a.administrator_email::text), ''),
                        NULLIF(trim(a.clinic_email::text), ''),
                        NULLIF(trim(c.email::text), '')
                      ) AS account_email
                 FROM clinics c
                 LEFT JOIN LATERAL (
                   SELECT administrator_name, administrator_email, clinic_email
                     FROM clinic_applications
                    WHERE clinic_id = c.clinic_id
                    ORDER BY submitted_at DESC
                    LIMIT 1
                 ) a ON true
                WHERE c.clinic_id = $1 AND c.deleted_at IS NULL`,
              [clinicId],
            )
          ).rows[0];
          const canReconcile =
            repair?.clinic_status === 'Active' &&
            Boolean(repair?.administrator_name) &&
            Boolean(repair?.account_email);
          return {
            status: 'NotProvisioned',
            canResend: canReconcile,
            email: repair?.account_email ?? null,
            reason: canReconcile
              ? 'Administrator provisioning can be repaired from the registration Account Email.'
              : 'A valid registration Account Email and administrator name are required before provisioning can be repaired.',
          };
        }
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
        const existingUser = (
          await client.query(
            `SELECT * FROM users
              WHERE clinic_id = $1 AND account_type = 'ClinicAdministrator'
                AND deleted_at IS NULL
              ORDER BY created_at LIMIT 1 FOR UPDATE`,
            [context.clinicId],
          )
        ).rows[0];
        if (existingUser?.status === 'Active') {
          throw serviceError(
            'activation_not_required',
            'This Clinic Administrator is already active.',
            409,
          );
        }
        const reconciliation = await this.provisionOnApproval(client, {
          clinicId: context.clinicId,
          clinicName: clinic.name,
          actorUserId: context.actorUserId,
          sessionId: context.sessionId,
          ipAddress: context.ipAddress,
        });
        const user = reconciliation.user;
        const token =
          reconciliation.issued ??
          await this.#issueToken(client, {
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
          action: existingUser
            ? 'administrator.activation_resent'
            : 'administrator.provisioned_and_activation_sent',
          newSummary: {
            expiresAt: token.expiresAt,
            administratorProvisioned: !existingUser,
            recipientEmail: user.email,
          },
          sessionId: context.sessionId,
          ipAddress: context.ipAddress,
        });
        return token;
      },
    );
    return this.deliverIssuedToken(issued);
  }

  async inviteStaff(context) {
    const issued = await withTenantTransaction(this.pool, {
      clinicId: context.clinicId,
      userId: context.actorUserId,
      isPlatformOwner: false,
    }, async (client) => {
      const actor = (await client.query(
        `SELECT r.code FROM clinic_memberships cm
           JOIN roles r ON r.role_id=cm.role_id AND r.clinic_id=cm.clinic_id
          WHERE cm.clinic_id=$1 AND cm.user_id=$2
            AND cm.membership_status='Active' AND cm.deleted_at IS NULL`,
        [context.clinicId, context.actorUserId],
      )).rows[0];
      if (actor?.code !== 'clinic_administrator') {
        throw serviceError('staff_invitation_forbidden', 'Only an active Clinic Administrator can invite staff.', 403);
      }
      const role = (await client.query(
        `SELECT role_id, name, code FROM roles
          WHERE clinic_id=$1 AND role_id=$2
            AND deleted_at IS NULL`,
        [context.clinicId, context.roleId],
      )).rows[0];
      if (!role || role.code === 'clinic_administrator') {
        throw serviceError('invalid_clinic_role', 'Choose a valid staff role for this clinic.', 400);
      }
      const email = context.email.trim().toLowerCase();
      const existing = (await client.query(
        'SELECT * FROM users WHERE email=$1 AND deleted_at IS NULL FOR UPDATE',
        [email],
      )).rows[0];
      if (existing) {
        if (existing.clinic_id === context.clinicId && existing.status === 'PendingActivation') {
          throw serviceError('invitation_pending', 'An invitation is already pending for this email.', 409);
        }
        if (existing.clinic_id === context.clinicId && existing.status === 'Active') {
          throw serviceError('email_in_use', 'This email already belongs to an active staff account.', 409);
        }
        throw serviceError('email_in_use', 'An AVERA account already uses this email address.', 409);
      }
      const staffNumber = await allocateClinicStaffNumber(
        client,
        context.clinicId,
      );
      const user = (await client.query(
        `INSERT INTO users
           (clinic_id, full_name, email, phone, password_hash, account_type,
            status, role_id, created_by, updated_by)
         VALUES ($1,$2,$3,$4,NULL,'ClinicStaff','PendingActivation',$5,$6,$6)
         RETURNING *`,
        [context.clinicId, context.fullName.trim(), email,
          context.phone || null, role.role_id, context.actorUserId],
      )).rows[0];
      await client.query(
        `INSERT INTO clinic_memberships
           (user_id, clinic_id, role_id, membership_status, invited_at,
            created_by, updated_by)
         VALUES ($1,$2,$3,'Invited',now(),$4,$4)`,
        [user.user_id, context.clinicId, role.role_id, context.actorUserId],
      );
      await client.query(
        `INSERT INTO staff_profiles
           (user_id, clinic_id, professional_title, staff_number,
            created_at, updated_at)
         VALUES ($1,$2,$3,$4,now(),now())`,
        [user.user_id, context.clinicId, context.professionalTitle, staffNumber],
      );
      const clinic = (await client.query(
        'SELECT name FROM clinics WHERE clinic_id=$1 AND deleted_at IS NULL',
        [context.clinicId],
      )).rows[0];
      const token = await this.#issueStaffToken(client, {
        clinicId: context.clinicId,
        user,
        clinicName: clinic.name,
        roleName: role.name,
        professionalTitle: context.professionalTitle,
        staffNumber,
        actorUserId: context.actorUserId,
        ipAddress: context.ipAddress,
      });
      await writeAudit(client, {
        clinicId: context.clinicId,
        actingUserId: context.actorUserId,
        targetType: 'User', targetId: user.user_id,
        action: 'staff.invited',
        newSummary: {
          email,
          roleId: role.role_id,
          professionalTitle: context.professionalTitle,
          staffNumber,
          status: 'PendingActivation',
        },
        sessionId: context.sessionId, ipAddress: context.ipAddress,
      });
      return token;
    });
    const delivery = await this.deliverStaffToken(issued);
    return {
      userId: issued.userId,
      status: 'PendingActivation',
      staffNumber: issued.staffNumber,
      delivery,
    };
  }

  async resendStaff(context) {
    const issued = await withTenantTransaction(this.pool, {
      clinicId: context.clinicId,
      userId: context.actorUserId,
      isPlatformOwner: false,
    }, async (client) => {
      const actor = (await client.query(
        `SELECT r.code FROM clinic_memberships cm
           JOIN roles r ON r.role_id=cm.role_id AND r.clinic_id=cm.clinic_id
          WHERE cm.clinic_id=$1 AND cm.user_id=$2
            AND cm.membership_status='Active' AND cm.deleted_at IS NULL`,
        [context.clinicId, context.actorUserId],
      )).rows[0];
      if (actor?.code !== 'clinic_administrator') {
        throw serviceError('staff_invitation_forbidden', 'Only an active Clinic Administrator can resend staff invitations.', 403);
      }
      const target = (await client.query(
        `SELECT u.*, c.name AS clinic_name, r.name AS role_name,
                sp.professional_title, sp.staff_number
           FROM users u JOIN clinics c ON c.clinic_id=u.clinic_id
           JOIN roles r ON r.role_id=u.role_id AND r.clinic_id=u.clinic_id
           JOIN staff_profiles sp ON sp.user_id=u.user_id
          WHERE u.user_id=$1 AND u.clinic_id=$2
            AND u.account_type='ClinicStaff' AND u.status='PendingActivation'
            AND u.deleted_at IS NULL FOR UPDATE OF u`,
        [context.targetUserId, context.clinicId],
      )).rows[0];
      if (!target) throw serviceError('activation_not_required', 'This staff invitation cannot be resent.', 409);
      const token = await this.#issueStaffToken(client, {
        clinicId: context.clinicId, user: target,
        clinicName: target.clinic_name, roleName: target.role_name,
        professionalTitle: target.professional_title,
        staffNumber: target.staff_number,
        actorUserId: context.actorUserId,
        ipAddress: context.ipAddress,
      });
      await writeAudit(client, {
        clinicId: context.clinicId, actingUserId: context.actorUserId,
        targetType: 'User', targetId: target.user_id,
        action: 'staff.invitation_resent', newSummary: { expiresAt: token.expiresAt },
        sessionId: context.sessionId, ipAddress: context.ipAddress,
      });
      return token;
    });
    return this.deliverStaffToken(issued);
  }

  async inspectStaff(rawToken) {
    return withTenantTransaction(this.pool, { isPlatformOwner: true }, async (client) => {
      const row = await this.#staffTokenRecord(rawToken, false, client);
      this.#assertStaffUsable(row);
      return { clinicName: row.clinic_name, staffName: row.full_name,
        email: row.email, roleName: row.role_name, expiresAt: row.expires_at };
    });
  }

  async activateStaff({ rawToken, password, confirmPassword, ipAddress }) {
    if (password !== confirmPassword) throw serviceError('password_mismatch', 'Passwords do not match.', 400);
    const passwordError = validatePassword(password);
    if (passwordError) throw serviceError('weak_password', passwordError, 400);
    return withTenantTransaction(this.pool, { isPlatformOwner: true }, async (client) => {
      const row = await this.#staffTokenRecord(rawToken, true, client);
      this.#assertStaffUsable(row);
      const now = new Date();
      await client.query(
        `UPDATE users SET password_hash=$2, status='Active',
                requires_password_change=false,
                email_verified_at=coalesce(email_verified_at,$3),
                failed_login_count=0, locked_until=NULL,
                updated_at=$3, revision=revision+1
          WHERE user_id=$1`,
        [row.user_id, await hashPassword(password), now],
      );
      await client.query(
        `UPDATE clinic_memberships SET membership_status='Active', activated_at=$2,
                updated_at=$2, revision=revision+1
          WHERE user_id=$1 AND clinic_id=$3 AND deleted_at IS NULL`,
        [row.user_id, now, row.clinic_id],
      );
      await client.query(
        `UPDATE activation_tokens
            SET used_at=CASE WHEN token_id=$2 THEN $3 ELSE used_at END,
                revoked_at=CASE WHEN token_id<>$2 AND used_at IS NULL THEN $3 ELSE revoked_at END
          WHERE user_id=$1 AND purpose=$4`,
        [row.user_id, row.token_id, now, staffPurpose],
      );
      await writeAudit(client, {
        clinicId: row.clinic_id, actingUserId: row.user_id,
        targetType: 'User', targetId: row.user_id, action: 'staff.activated',
        previousSummary: { status: 'PendingActivation' },
        newSummary: { status: 'Active' }, ipAddress,
      });
      return { activated: true, email: row.email, mfaEnrollmentRecommended: true };
    });
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

  async deliverStaffToken(issued) {
    if (!this.deliveryService.configured) {
      return { status: 'DeliveryUnavailable', expiresAt: issued.expiresAt };
    }
    try {
      const delivery = await this.deliveryService.sendStaffActivation({
        to: issued.email, staffName: issued.fullName,
        clinicName: issued.clinicName,
        roleName: issued.roleName,
        professionalTitle: issued.professionalTitle,
        staffNumber: issued.staffNumber,
        activationUrl: this.#staffActivationUrl(issued.rawToken),
        expiresAt: issued.expiresAt,
        idempotencyKey: `staff-activation-${issued.tokenId}`,
      });
      await this.pool.query(
        `UPDATE activation_tokens SET delivery_method='email',
                delivered_at=now(), delivery_reference=$2 WHERE token_id=$1`,
        [issued.tokenId, delivery.reference],
      );
      return { status: 'EmailSent', expiresAt: issued.expiresAt };
    } catch (_) {
      await this.pool.query(
        `UPDATE activation_tokens SET delivery_method='email_failed' WHERE token_id=$1`,
        [issued.tokenId],
      );
      return { status: 'DeliveryFailed', expiresAt: issued.expiresAt };
    }
  }

  async #issueStaffToken(client, context) {
    const now = new Date();
    await client.query(
      `UPDATE activation_tokens SET revoked_at=$3
        WHERE user_id=$1 AND purpose=$2 AND used_at IS NULL AND revoked_at IS NULL`,
      [context.user.user_id, staffPurpose, now],
    );
    const rawToken = randomBytes(32).toString('base64url');
    const expiresAt = new Date(now.getTime() + this.environment.ACTIVATION_TOKEN_TTL_MINUTES * 60_000);
    const inserted = (await client.query(
      `INSERT INTO activation_tokens
         (user_id, clinic_id, purpose, token_hash, expires_at,
          requested_from_ip, metadata)
       VALUES ($1,$2,$3,$4,$5,$6,jsonb_build_object('issuedBy',$7::text))
       RETURNING token_id`,
      [context.user.user_id, context.clinicId, staffPurpose,
        hashToken(rawToken), expiresAt, context.ipAddress ?? null,
        context.actorUserId],
    )).rows[0];
    return { tokenId: inserted.token_id, userId: context.user.user_id,
      rawToken, expiresAt, email: context.user.email,
      fullName: context.user.full_name, clinicName: context.clinicName,
      roleName: context.roleName,
      professionalTitle: context.professionalTitle,
      staffNumber: context.staffNumber };
  }

  async #staffTokenRecord(rawToken, forUpdate, client) {
    return (await client.query(
      `SELECT t.*, u.full_name, u.email, u.status AS user_status,
              c.name AS clinic_name, c.status AS clinic_status,
              r.name AS role_name, cm.membership_status
         FROM activation_tokens t
         JOIN users u ON u.user_id=t.user_id
         JOIN clinics c ON c.clinic_id=t.clinic_id
         JOIN clinic_memberships cm ON cm.user_id=u.user_id AND cm.clinic_id=t.clinic_id
         LEFT JOIN roles r ON r.role_id=cm.role_id
        WHERE t.token_hash=$1 AND t.purpose=$2
        ${forUpdate ? 'FOR UPDATE OF t, u, cm' : ''}`,
      [hashToken(rawToken), staffPurpose],
    )).rows[0];
  }

  #assertStaffUsable(row) {
    if (!row) throw serviceError('activation_invalid', 'This activation link is invalid.', 400);
    if (row.used_at) throw serviceError('activation_used', 'This activation link has already been used.', 409);
    if (row.revoked_at) throw serviceError('activation_revoked', 'This activation link is no longer valid.', 409);
    if (new Date(row.expires_at) <= new Date()) throw serviceError('activation_expired', 'This activation link has expired.', 410);
    if (row.user_status !== 'PendingActivation' || row.membership_status !== 'Invited' || row.clinic_status !== 'Active') {
      throw serviceError('activation_unavailable', 'This account is not available for activation.', 409);
    }
  }

  #staffActivationUrl(rawToken) {
    const url = new URL(this.environment.AVERA_STAFF_ACTIVATION_BASE_URL);
    url.searchParams.set('token', rawToken);
    return url.toString();
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

  async sendStaffActivation(message) {
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
        subject: `Activate your ${message.clinicName} staff account`,
        text: staffActivationEmailText(message),
      }),
    });
    if (!response.ok) throw new Error('Activation email delivery failed.');
    const body = await response.json();
    return { reference: body.id ?? null };
  }

  async sendClinicDeletionCode(message) {
    if (!this.configured) throw new Error('Deletion email is not configured.');
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
        subject: `Confirm mutual deletion of ${message.clinicName}`,
        text: clinicDeletionEmailText(message),
      }),
    });
    if (!response.ok) throw new Error('Deletion email delivery failed.');
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

function staffActivationEmailText(message) {
  return [
    `Hello ${message.staffName},`, '',
    `${message.clinicName} invited you to join its team on AVERA.`,
    `Assigned role: ${message.roleName}.`,
    `Professional title: ${message.professionalTitle}.`,
    `Staff number: ${message.staffNumber}.`,
    'Create your password using this secure single-use link:',
    message.activationUrl, '',
    `This link expires at ${new Date(message.expiresAt).toISOString()}.`,
    'If you were not expecting this invitation, ignore this email.',
  ].join('\n');
}

function clinicDeletionEmailText(message) {
  return [
    `AVERA received a Platform Owner request to mutually delete ${message.clinicName}.`,
    '',
    `Confirmation code: ${message.code}`,
    '',
    `This code expires at ${new Date(message.expiresAt).toISOString()}.`,
    'Share this code with the AVERA Platform Owner only if the clinic agrees to deletion.',
    'After confirmation, clinic access is revoked and this Account Email can be used for a new registration.',
    'Payment and audit records remain preserved for accountability.',
    message.reason ? `Reason supplied: ${message.reason}` : '',
    '',
    'If the clinic did not agree to deletion, do not share the code and contact AVERA support.',
  ].filter(Boolean).join('\n');
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
