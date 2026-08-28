import { randomInt, randomUUID } from 'node:crypto';
import { withTenantTransaction } from '../database/pool.js';
import { hashToken } from '../security/tokens.js';

const challengeMinutes = 10;
const challengeAttempts = 5;
const resumableApplicationStatuses = new Set(['Draft', 'AwaitingPayment', 'Pending']);

export class SocialAuthService {
  constructor({ pool, tokenVerifier, deliveryService }) {
    this.pool = pool;
    this.tokenVerifier = tokenVerifier;
    this.deliveryService = deliveryService;
  }

  async begin({ provider, idToken, nonce, existingEmail, ipAddress }) {
    const identity = await this.tokenVerifier.verify({ provider, idToken, nonce });
    const requestedEmail = normalizeOptionalEmail(existingEmail);
    const providerEmail = identity.emailVerified ? identity.email : null;
    const targetEmail = requestedEmail ?? (
      identity.isPrivateRelay ? null : providerEmail
    );

    const result = await withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const linked = (
          await client.query(
            `SELECT p.user_id, u.status AS user_status, u.account_type
               FROM user_auth_providers p
               JOIN users u ON u.user_id = p.user_id AND u.deleted_at IS NULL
              WHERE p.provider_type = $1 AND p.provider_subject = $2`,
            [identity.provider, identity.subject],
          )
        ).rows[0];
        if (linked) {
          await client.query(
            `UPDATE user_auth_providers
                SET last_used_at = now(), provider_email = COALESCE($3, provider_email),
                    updated_at = now()
              WHERE provider_type = $1 AND provider_subject = $2`,
            [identity.provider, identity.subject, providerEmail],
          );
          return userOutcome(linked);
        }

        if (!targetEmail) {
          return {
            action: 'account_email_required',
            provider: identity.provider,
            message: 'Enter your existing AVERA account email to securely connect Apple.',
          };
        }

        const user = (
          await client.query(
            `SELECT user_id, status AS user_status, account_type
               FROM users
              WHERE lower(email::text) = lower($1) AND deleted_at IS NULL`,
            [targetEmail],
          )
        ).rows[0];
        if (user) {
          return this.#createChallenge(client, {
            identity,
            providerEmail,
            targetEmail,
            targetUserId: user.user_id,
            targetApplicationId: null,
            ipAddress,
          });
        }

        const application = await findApplication(client, targetEmail);
        if (application) {
          const providerOwnsEmail = providerEmail === targetEmail;
          if (providerOwnsEmail && !requestedEmail) return applicationOutcome(application);
          return this.#createChallenge(client, {
            identity,
            providerEmail,
            targetEmail,
            targetUserId: null,
            targetApplicationId: application.application_id,
            ipAddress,
          });
        }

        return {
          action: 'registration_required',
          provider: identity.provider,
          email: targetEmail,
          message: 'No AVERA clinic account was found for this email.',
        };
      },
    );

    if (result.action === 'verification_required') {
      await this.#deliverChallenge(result);
      return publicChallenge(result);
    }
    return result;
  }

  async verify({ challengeId, code }) {
    const result = await withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => {
        const challenge = (
          await client.query(
            `SELECT * FROM auth_provider_link_challenges
              WHERE challenge_id = $1
              FOR UPDATE`,
            [challengeId],
          )
        ).rows[0];
        if (!challenge || challenge.used_at || challenge.revoked_at) {
          throw socialError('provider_link_code_used', 'This verification code is no longer available.', 409);
        }
        if (new Date(challenge.expires_at).getTime() <= Date.now()) {
          throw socialError('provider_link_code_expired', 'This verification code has expired.', 410);
        }
        if (challenge.attempts_remaining <= 0) {
          throw socialError('provider_link_attempts_exhausted', 'Too many verification attempts were made.', 429);
        }
        if (challenge.code_hash !== challengeHash(challengeId, code)) {
          await client.query(
            `UPDATE auth_provider_link_challenges
                SET attempts_remaining = attempts_remaining - 1
              WHERE challenge_id = $1`,
            [challengeId],
          );
          throw socialError('provider_link_code_invalid', 'The verification code is incorrect.', 400);
        }

        if (challenge.target_user_id) {
          const conflicting = (
            await client.query(
              `SELECT user_id FROM user_auth_providers
                WHERE provider_type = $1 AND provider_subject = $2`,
              [challenge.provider_type, challenge.provider_subject],
            )
          ).rows[0];
          if (conflicting && conflicting.user_id !== challenge.target_user_id) {
            throw socialError('provider_identity_conflict', 'This provider identity is linked to another AVERA user.', 409);
          }
          await client.query(
            `INSERT INTO user_auth_providers
               (user_id, provider_type, provider_subject, provider_email,
                verified_at, linked_at, last_used_at)
             VALUES ($1, $2, $3, $4, now(), now(), now())
             ON CONFLICT (user_id, provider_type) DO UPDATE
               SET provider_subject = EXCLUDED.provider_subject,
                   provider_email = EXCLUDED.provider_email,
                   verified_at = now(), last_used_at = now(), updated_at = now()`,
            [
              challenge.target_user_id,
              challenge.provider_type,
              challenge.provider_subject,
              challenge.provider_email,
            ],
          );
        }
        await client.query(
          `UPDATE auth_provider_link_challenges SET used_at = now()
            WHERE challenge_id = $1`,
          [challengeId],
        );

        if (challenge.target_user_id) {
          const user = (
            await client.query(
              `SELECT user_id, status AS user_status, account_type
                 FROM users WHERE user_id = $1 AND deleted_at IS NULL`,
              [challenge.target_user_id],
            )
          ).rows[0];
          return userOutcome(user);
        }
        const application = (
          await client.query(
            `SELECT * FROM clinic_applications WHERE application_id = $1`,
            [challenge.target_application_id],
          )
        ).rows[0];
        return applicationOutcome(application);
      },
    );
    return result;
  }

  async #createChallenge(
    client,
    {
      identity,
      providerEmail,
      targetEmail,
      targetUserId,
      targetApplicationId,
      ipAddress,
    },
  ) {
    const challengeId = randomUUID();
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const expiresAt = new Date(Date.now() + challengeMinutes * 60_000);
    await client.query(
      `UPDATE auth_provider_link_challenges
          SET revoked_at = now()
        WHERE provider_type = $1 AND provider_subject = $2
          AND used_at IS NULL AND revoked_at IS NULL`,
      [identity.provider, identity.subject],
    );
    await client.query(
      `INSERT INTO auth_provider_link_challenges
         (challenge_id, provider_type, provider_subject, provider_email,
          target_email, target_user_id, target_application_id, code_hash,
          attempts_remaining, expires_at, requested_from_ip)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
      [
        challengeId,
        identity.provider,
        identity.subject,
        providerEmail,
        targetEmail,
        targetUserId,
        targetApplicationId,
        challengeHash(challengeId, code),
        challengeAttempts,
        expiresAt,
        ipAddress ?? null,
      ],
    );
    return {
      action: 'verification_required',
      challengeId,
      provider: identity.provider,
      targetEmail,
      maskedEmail: maskEmail(targetEmail),
      code,
      expiresAt,
    };
  }

  async #deliverChallenge(challenge) {
    if (!this.deliveryService.configured) {
      await this.pool.query(
        'UPDATE auth_provider_link_challenges SET revoked_at = now() WHERE challenge_id = $1',
        [challenge.challengeId],
      );
      throw socialError(
        'provider_link_email_unavailable',
        'AVERA email verification is not configured. Use email and password for now.',
        503,
      );
    }
    try {
      await this.deliveryService.sendProviderLinkCode({
        to: challenge.targetEmail,
        provider: challenge.provider,
        code: challenge.code,
        expiresAt: challenge.expiresAt,
        idempotencyKey: `provider-link-${challenge.challengeId}`,
      });
    } catch (_) {
      await this.pool.query(
        'UPDATE auth_provider_link_challenges SET revoked_at = now() WHERE challenge_id = $1',
        [challenge.challengeId],
      );
      throw socialError('provider_link_email_failed', 'The verification email could not be sent.', 502);
    }
  }
}

async function findApplication(client, email) {
  return (
    await client.query(
      `SELECT * FROM clinic_applications
        WHERE lower(administrator_email::text) = lower($1)
        ORDER BY updated_at DESC, submitted_at DESC
        LIMIT 1`,
      [email],
    )
  ).rows[0];
}

function applicationOutcome(application) {
  const paid = ['Paid', 'TestVerified'].includes(application.payment_status);
  if (paid || ['PendingApproval', 'Approved'].includes(application.status)) {
    return {
      action: application.status === 'Approved' ? 'activation_required' : 'application_pending',
      application,
      message: application.status === 'Approved'
        ? 'Your clinic is approved and awaiting administrator activation.'
        : 'Payment was received. Your clinic application is awaiting approval.',
    };
  }
  if (resumableApplicationStatuses.has(application.status)) {
    return {
      action: 'resume_registration',
      application,
      message: 'Continue your existing clinic registration.',
    };
  }
  return {
    action: 'application_restricted',
    application,
    message: restrictedApplicationMessage(application.status),
  };
}

function restrictedApplicationMessage(status) {
  if (status === 'Rejected') {
    return 'This clinic application was not approved. Contact AVERA support before starting another registration.';
  }
  if (status === 'Suspended') {
    return 'This clinic application is suspended. Contact AVERA support for assistance.';
  }
  if (status === 'Archived') {
    return 'This clinic application is archived. Contact AVERA support before starting another registration.';
  }
  return 'This clinic application cannot continue in its current state. Contact AVERA support for assistance.';
}

function userOutcome(user) {
  if (!user) throw socialError('account_not_found', 'The linked AVERA account was not found.', 404);
  if (user.user_status === 'PendingActivation' || user.user_status === 'Invited') {
    return {
      action: 'staff_activation_required',
      userId: user.user_id,
      message: user.account_type === 'ClinicAdministrator'
        ? 'Activate your Clinic Administrator account using the secure link sent by AVERA.'
        : 'Complete the staff activation sent by your clinic administrator.',
    };
  }
  return { action: 'sign_in', userId: user.user_id };
}

function publicChallenge(challenge) {
  return {
    action: challenge.action,
    challengeId: challenge.challengeId,
    provider: challenge.provider,
    maskedEmail: challenge.maskedEmail,
    expiresAt: challenge.expiresAt,
    message: `A verification code was sent to ${challenge.maskedEmail}.`,
  };
}

function challengeHash(challengeId, code) {
  return hashToken(`${challengeId}:${String(code).trim()}`);
}

function normalizeOptionalEmail(value) {
  const email = String(value ?? '').trim().toLowerCase();
  return email || null;
}

function maskEmail(email) {
  const [name, domain] = email.split('@');
  if (!domain) return 'your email';
  return `${name.slice(0, 2)}${'*'.repeat(Math.max(2, name.length - 2))}@${domain}`;
}

function socialError(code, message, statusCode = 400) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}
