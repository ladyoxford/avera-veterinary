import crypto from 'node:crypto';
import { withTenantTransaction } from '../database/pool.js';

const CURRENT_STATUSES = [
  'Trial',
  'Pending Payment',
  'Active',
  'Past Due',
  'Non-renewing',
];

export class SubscriptionService {
  constructor({ pool, environment, gateway }) {
    this.pool = pool;
    this.environment = environment;
    this.gateway = gateway;
  }

  async listPlans() {
    const result = await this.pool.query(
      `SELECT plan_id, plan_key, display_name, tagline, description,
              monthly_amount_minor, annual_amount_minor, currency,
              is_recommended, sort_order, entitlements
         FROM plans
        WHERE active = true
        ORDER BY sort_order, display_name`,
    );
    return result.rows.map((row) => {
      const monthlyPlanCode = this.#configuredPlanCode(row.plan_key, 'monthly');
      const annualPlanCode = this.#configuredPlanCode(row.plan_key, 'annual');
      return {
        id: row.plan_id,
        code: row.plan_key,
        name: row.display_name,
        tagline: row.tagline,
        description: row.description,
        monthlyAmountMinor: toOptionalNumber(row.monthly_amount_minor),
        annualAmountMinor: toOptionalNumber(row.annual_amount_minor),
        currency: row.currency,
        monthlyCheckoutConfigured: Boolean(
          row.monthly_amount_minor != null && monthlyPlanCode && this.gateway.configured,
        ),
        annualCheckoutConfigured: Boolean(
          row.annual_amount_minor != null && annualPlanCode && this.gateway.configured,
        ),
        isRecommended: row.is_recommended,
        entitlements: row.entitlements,
      };
    });
  }

  async getClinicSubscription(auth, clinicId) {
    return withTenantTransaction(
      this.pool,
      tenantContext(auth, clinicId),
      async (client) => {
        const result = await client.query(
          `SELECT s.*, p.display_name AS plan_name
             FROM subscriptions s
             JOIN plans p ON p.plan_key = s.plan
            WHERE s.clinic_id = $1
              AND s.status = ANY($2::text[])
            ORDER BY s.updated_at DESC
            LIMIT 1`,
          [clinicId, CURRENT_STATUSES],
        );
        return result.rows[0] ? mapSubscription(result.rows[0]) : null;
      },
    );
  }

  async listPayments(auth, clinicId) {
    return withTenantTransaction(
      this.pool,
      tenantContext(auth, clinicId),
      async (client) => {
        const result = await client.query(
          `SELECT reference, plan_code, billing_cycle, amount_minor, currency,
                  status, payment_channel, paid_at, created_at
             FROM subscription_payment_transactions
            WHERE clinic_id = $1
            ORDER BY created_at DESC
            LIMIT 100`,
          [clinicId],
        );
        return result.rows.map(mapPayment);
      },
    );
  }

  async initializeCheckout({ auth, clinicId, planCode, billingCycle }) {
    const cycle = normalizeCycle(billingCycle);
    const result = await withTenantTransaction(
      this.pool,
      tenantContext(auth, clinicId),
      async (client) => {
        const plan = (
          await client.query(
            `SELECT plan_key, display_name, monthly_amount_minor,
                    annual_amount_minor, currency
               FROM plans
              WHERE plan_key = $1 AND active = true`,
            [planCode],
          )
        ).rows[0];
        if (!plan) throw serviceError('invalid_plan', 'The selected plan is unavailable.', 400);
        if (
          String(plan.currency).toUpperCase() !==
          String(this.environment.PAYSTACK_CURRENCY ?? 'NGN').toUpperCase()
        ) {
          throw serviceError(
            'currency_not_configured',
            'The selected plan currency is not available for checkout.',
            409,
          );
        }
        const amountMinor =
          cycle === 'annual'
            ? plan.annual_amount_minor
            : plan.monthly_amount_minor;
        const gatewayPlanCode = this.#configuredPlanCode(plan.plan_key, cycle);
        if (amountMinor == null || !gatewayPlanCode || !this.gateway.configured) {
          throw serviceError(
            'plan_not_configured',
            `${plan.display_name} ${cycle} billing has not been configured.`,
            409,
          );
        }
        const billingUser = (
          await client.query(
            `SELECT email
               FROM users
              WHERE clinic_id = $1 AND status = 'Active' AND deleted_at IS NULL
              ORDER BY (account_type = 'ClinicAdministrator') DESC, created_at
              LIMIT 1`,
            [clinicId],
          )
        ).rows[0];
        if (!billingUser) {
          throw serviceError(
            'billing_contact_missing',
            'No active clinic billing contact is available.',
            409,
          );
        }
        const reference = createPaymentReference();
        await client.query(
          `INSERT INTO subscription_payment_transactions
             (clinic_id, reference, gateway, plan_code, billing_cycle,
              amount_minor, currency, status)
           VALUES ($1, $2, 'paystack', $3, $4, $5, $6, 'Pending')`,
          [
            clinicId,
            reference,
            plan.plan_key,
            cycle,
            Number(amountMinor),
            plan.currency,
          ],
        );
        await audit(client, {
          clinicId,
          auth,
          action: 'subscription.checkout_started',
          targetId: null,
          next: { reference, planCode: plan.plan_key, billingCycle: cycle },
        });
        return {
          email: billingUser.email,
          amountMinor: Number(amountMinor),
          currency: plan.currency,
          gatewayPlanCode,
          reference,
        };
      },
    );

    try {
      const checkout = await this.gateway.initializeCheckout({
        email: result.email,
        amountMinor: result.amountMinor,
        currency: result.currency,
        planCode: result.gatewayPlanCode,
        reference: result.reference,
        callbackUrl:
          this.environment.paymentCallbackUrl ??
          this.environment.PAYSTACK_CALLBACK_URL ??
          this.environment.APP_PAYMENT_CALLBACK_URL,
        metadata: { clinicId, planCode, billingCycle: cycle },
      });
      return {
        authorizationUrl: checkout.authorization_url,
        accessCode: checkout.access_code,
        reference: result.reference,
      };
    } catch (error) {
      await this.pool.query(
        `UPDATE subscription_payment_transactions
            SET status = 'Failed', updated_at = now(),
                gateway_response_summary = jsonb_build_object('reason', $2::text)
          WHERE reference = $1 AND status = 'Pending'`,
        [result.reference, safeGatewayReason(error)],
      );
      throw serviceError(
        error.code ?? 'gateway_unavailable',
        'Paystack checkout could not be started. Please try again.',
        502,
      );
    }
  }

  async verifyAndApply(reference, auth = null) {
    const expected = (
      await this.pool.query(
        `SELECT * FROM subscription_payment_transactions WHERE reference = $1`,
        [reference],
      )
    ).rows[0];
    if (!expected) {
      throw serviceError('payment_not_found', 'The payment reference was not found.', 404);
    }
    if (
      auth &&
      auth.clinicId !== expected.clinic_id &&
      auth.accountType !== 'PlatformOwner' &&
      auth.accountType !== 'PlatformAdministrator'
    ) {
      throw serviceError(
        'forbidden',
        'You cannot manage subscriptions for this clinic.',
        403,
      );
    }
    if (expected.status === 'Successful') {
      return this.#verificationResult(expected);
    }
    const verified = await this.gateway.verifyPayment(reference);
    if (
      ['pending', 'ongoing', 'processing'].includes(
        String(verified?.status).toLowerCase(),
      )
    ) {
      throw serviceError(
        'payment_pending',
        'Paystack has not confirmed this payment yet.',
        409,
      );
    }
    const verificationError = validateVerifiedPayment(expected, verified);
    if (verificationError != null) {
      await this.#markVerificationFailure(expected, verified);
      throw serviceError(
        verificationError,
        'The payment details could not be verified.',
        409,
      );
    }
    const metadata = normalizeMetadata(verified.metadata);
    if (
      metadata.clinicId !== expected.clinic_id ||
      metadata.planCode !== expected.plan_code ||
      normalizeCycle(metadata.billingCycle) !== expected.billing_cycle
    ) {
      await this.#markVerificationFailure(expected, verified);
      throw serviceError(
        'payment_metadata_mismatch',
        'The payment does not match this clinic subscription.',
        409,
      );
    }
    return withTenantTransaction(
      this.pool,
      { clinicId: expected.clinic_id, isPlatformOwner: true },
      async (client) => {
        const locked = (
          await client.query(
            `SELECT * FROM subscription_payment_transactions
              WHERE reference = $1 FOR UPDATE`,
            [reference],
          )
        ).rows[0];
        if (locked.status === 'Successful') return this.#verificationResult(locked);
        const paidAt = verified.paid_at ? new Date(verified.paid_at) : new Date();
        const periodEnd = addBillingPeriod(paidAt, locked.billing_cycle);
        let subscription = (
          await client.query(
            `SELECT * FROM subscriptions
              WHERE clinic_id = $1 AND status = ANY($2::text[])
              ORDER BY updated_at DESC LIMIT 1 FOR UPDATE`,
            [locked.clinic_id, CURRENT_STATUSES],
          )
        ).rows[0];
        if (subscription) {
          subscription = (
            await client.query(
              `UPDATE subscriptions
                  SET plan = $2, status = 'Active', billing_cycle = $3,
                      gateway = 'paystack', current_period_start = $4,
                      current_period_ends_at = $5, next_billing_date = $5,
                      cancel_at_period_end = false, cancelled_at = NULL,
                      updated_at = now()
                WHERE subscription_id = $1 RETURNING *`,
              [
                subscription.subscription_id,
                locked.plan_code,
                locked.billing_cycle,
                paidAt,
                periodEnd,
              ],
            )
          ).rows[0];
        } else {
          subscription = (
            await client.query(
              `INSERT INTO subscriptions
                 (clinic_id, plan, status, billing_cycle, gateway,
                  current_period_start, current_period_ends_at, next_billing_date)
               VALUES ($1, $2, 'Active', $3, 'paystack', $4, $5, $5)
               RETURNING *`,
              [
                locked.clinic_id,
                locked.plan_code,
                locked.billing_cycle,
                paidAt,
                periodEnd,
              ],
            )
          ).rows[0];
        }
        await client.query(
          `UPDATE subscription_payment_transactions
              SET subscription_id = $2, status = 'Successful',
                  payment_channel = $3, gateway_transaction_id = $4,
                  paid_at = $5, updated_at = now(),
                  gateway_response_summary = $6::jsonb
            WHERE reference = $1`,
          [
            reference,
            subscription.subscription_id,
            verified.channel ?? null,
            verified.id == null ? null : String(verified.id),
            paidAt,
            JSON.stringify({ gatewayStatus: verified.status }),
          ],
        );
        await client.query(
          `UPDATE clinics SET subscription_plan = $2, updated_at = now()
            WHERE clinic_id = $1`,
          [locked.clinic_id, locked.plan_code],
        );
        await audit(client, {
          clinicId: locked.clinic_id,
          auth: null,
          action: 'subscription.payment_succeeded',
          targetId: subscription.subscription_id,
          next: { reference, planCode: locked.plan_code },
        });
        return {
          payment: { ...mapPayment(locked), status: 'Successful', paidAt },
          subscription: mapSubscription(subscription),
        };
      },
    );
  }

  async cancelRenewal(auth, clinicId) {
    return this.#setRenewal(auth, clinicId, false);
  }

  async reactivateRenewal(auth, clinicId) {
    return this.#setRenewal(auth, clinicId, true);
  }

  async changePlan(auth, clinicId, planCode, billingCycle) {
    return this.initializeCheckout({ auth, clinicId, planCode, billingCycle });
  }

  async persistWebhook({ event, rawBody, payloadHash }) {
    const identity = webhookIdentity(event, payloadHash);
    const inserted = await this.pool.query(
      `INSERT INTO payment_webhook_events
         (gateway, event_type, event_identity, payload_hash)
       VALUES ('paystack', $1, $2, $3)
       ON CONFLICT (gateway, event_identity) DO NOTHING
       RETURNING payment_webhook_event_id`,
      [event.event, identity, payloadHash],
    );
    if (inserted.rowCount === 0) return { duplicate: true };
    try {
      if (event.event === 'charge.success' && event.data?.reference) {
        await this.verifyAndApply(event.data.reference);
      } else {
        await this.#applySubscriptionEvent(event);
      }
      await this.pool.query(
        `UPDATE payment_webhook_events
            SET processing_status = 'Processed', processed_at = now()
          WHERE payment_webhook_event_id = $1`,
        [inserted.rows[0].payment_webhook_event_id],
      );
      return { duplicate: false };
    } catch (error) {
      await this.pool.query(
        `UPDATE payment_webhook_events
            SET processing_status = 'Failed', processed_at = now()
          WHERE payment_webhook_event_id = $1`,
        [inserted.rows[0].payment_webhook_event_id],
      );
      throw error;
    }
  }

  async #setRenewal(auth, clinicId, enabled) {
    return withTenantTransaction(
      this.pool,
      tenantContext(auth, clinicId),
      async (client) => {
        const subscription = (
          await client.query(
            `SELECT * FROM subscriptions
              WHERE clinic_id = $1 AND status = ANY($2::text[])
              ORDER BY updated_at DESC LIMIT 1 FOR UPDATE`,
            [clinicId, CURRENT_STATUSES],
          )
        ).rows[0];
        if (!subscription) {
          throw serviceError('subscription_not_found', 'No active subscription was found.', 404);
        }
        if (subscription.gateway_subscription_code && subscription.gateway_email_token) {
          if (enabled) {
            await this.gateway.reactivateSubscription({
              subscriptionCode: subscription.gateway_subscription_code,
              emailToken: subscription.gateway_email_token,
            });
          } else {
            await this.gateway.cancelRenewal({
              subscriptionCode: subscription.gateway_subscription_code,
              emailToken: subscription.gateway_email_token,
            });
          }
        }
        const updated = (
          await client.query(
            `UPDATE subscriptions
                SET cancel_at_period_end = $2,
                    status = CASE WHEN $2 THEN 'Non-renewing' ELSE 'Active' END,
                    cancelled_at = CASE WHEN $2 THEN now() ELSE NULL END,
                    updated_at = now()
              WHERE subscription_id = $1 RETURNING *`,
            [subscription.subscription_id, !enabled],
          )
        ).rows[0];
        await audit(client, {
          clinicId,
          auth,
          action: enabled
            ? 'subscription.renewal_reactivated'
            : 'subscription.renewal_disabled',
          targetId: updated.subscription_id,
          previous: { cancelAtPeriodEnd: subscription.cancel_at_period_end },
          next: { cancelAtPeriodEnd: updated.cancel_at_period_end },
        });
        return mapSubscription(updated);
      },
    );
  }

  async #applySubscriptionEvent(event) {
    const data = event.data ?? {};
    const subscriptionCode = data.subscription_code ?? data.subscription?.subscription_code;
    if (!subscriptionCode) return;
    const updates = {
      'invoice.payment_failed': ['Past Due', false],
      'subscription.not_renew': ['Non-renewing', true],
      'subscription.disable': ['Cancelled', true],
    }[event.event];
    if (!updates) return;
    await this.pool.query(
      `UPDATE subscriptions
          SET status = $2, cancel_at_period_end = $3, updated_at = now()
        WHERE gateway_subscription_code = $1`,
      [subscriptionCode, updates[0], updates[1]],
    );
  }

  async #markVerificationFailure(expected, verified) {
    await this.pool.query(
      `UPDATE subscription_payment_transactions
          SET status = 'Failed', updated_at = now(),
              gateway_response_summary = $2::jsonb
        WHERE reference = $1 AND status <> 'Successful'`,
      [
        expected.reference,
        JSON.stringify({
          gatewayStatus: verified?.status ?? 'unknown',
          mismatch: true,
        }),
      ],
    );
  }

  async #verificationResult(payment) {
    const subscription = await this.getClinicSubscription(
      { clinicId: payment.clinic_id, accountType: 'PlatformOwner' },
      payment.clinic_id,
    );
    return { payment: mapPayment(payment), subscription };
  }

  #configuredPlanCode(planKey, billingCycle) {
    const normalized = String(planKey).toUpperCase();
    const cycle = normalizeCycle(billingCycle).toUpperCase();
    return this.environment[`PAYSTACK_${normalized}_${cycle}_PLAN_CODE`] ?? null;
  }
}

export function serviceError(code, message, statusCode) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}

export function createPaymentReference({
  now = Date.now(),
  randomBytes = crypto.randomBytes,
} = {}) {
  return `AVERA-${now}-${randomBytes(8).toString('hex').toUpperCase()}`;
}

export function validateVerifiedPayment(expected, verified) {
  if (verified?.reference !== expected.reference) return 'payment_reference_mismatch';
  if (verified?.status !== 'success') return 'payment_not_successful';
  if (Number(verified?.amount) !== Number(expected.amount_minor)) {
    return 'payment_amount_mismatch';
  }
  if (
    String(verified?.currency).toUpperCase() !==
    String(expected.currency).toUpperCase()
  ) {
    return 'payment_currency_mismatch';
  }
  return null;
}

function tenantContext(auth, clinicId) {
  return {
    clinicId,
    isPlatformOwner:
      auth?.accountType === 'PlatformOwner' ||
      auth?.accountType === 'PlatformAdministrator',
  };
}

function normalizeCycle(value) {
  if (value !== 'monthly' && value !== 'annual') {
    throw serviceError('invalid_billing_cycle', 'Billing cycle must be monthly or annual.', 400);
  }
  return value;
}

function normalizeMetadata(value) {
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch (_) {
      return {};
    }
  }
  return value && typeof value === 'object' ? value : {};
}

function addBillingPeriod(date, cycle) {
  const result = new Date(date);
  if (cycle === 'annual') result.setUTCFullYear(result.getUTCFullYear() + 1);
  else result.setUTCMonth(result.getUTCMonth() + 1);
  return result;
}

function mapSubscription(row) {
  return {
    id: row.subscription_id,
    clinicId: row.clinic_id,
    planCode: row.plan,
    planName: row.plan_name ?? row.plan,
    billingCycle: row.billing_cycle,
    status: row.status,
    gateway: row.gateway,
    currentPeriodStart: row.current_period_start,
    currentPeriodEnd: row.current_period_ends_at,
    nextBillingDate: row.next_billing_date,
    cancelAtPeriodEnd: row.cancel_at_period_end,
    cancelledAt: row.cancelled_at,
    reference: row.subscription_id,
    updatedAt: row.updated_at,
  };
}

function mapPayment(row) {
  return {
    reference: row.reference,
    planCode: row.plan_code,
    billingCycle: row.billing_cycle,
    amountMinor: Number(row.amount_minor),
    currency: row.currency,
    status: row.status,
    paymentChannel: row.payment_channel,
    paidAt: row.paid_at,
    createdAt: row.created_at,
  };
}

function toOptionalNumber(value) {
  return value == null ? null : Number(value);
}

function safeGatewayReason(error) {
  return error?.code ?? 'gateway_request_failed';
}

function webhookIdentity(event, payloadHash) {
  const data = event.data ?? {};
  return String(
    data.id ??
      data.reference ??
      data.subscription_code ??
      `${event.event}:${payloadHash}`,
  );
}

async function audit(client, {
  clinicId,
  auth,
  action,
  targetId,
  previous,
  next,
}) {
  await client.query(
    `INSERT INTO audit_logs
       (clinic_id, acting_user_id, target_type, target_id, action,
        previous_summary, new_summary, session_id)
     VALUES ($1, $2, 'subscription', $3, $4, $5::jsonb, $6::jsonb, $7)`,
    [
      clinicId,
      auth?.userId ?? null,
      targetId,
      action,
      JSON.stringify(previous ?? {}),
      JSON.stringify(next ?? {}),
      auth?.sessionId ?? null,
    ],
  );
}
