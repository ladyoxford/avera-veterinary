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
  constructor({ pool, environment, gateway, onApplicationPaymentVerified }) {
    this.pool = pool;
    this.environment = environment;
    this.gateway = gateway;
    this.onApplicationPaymentVerified = onApplicationPaymentVerified;
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
    return result.rows.map((row) => this.#mapBillingPlan(row));
  }

  async getApplicationPaymentPlan({ applicationId, clinicId }) {
    return withTenantTransaction(
      this.pool,
      tenantContext({ accountType: 'PlatformOwner' }, clinicId),
      async (client) => {
        const row = (
          await client.query(
            `SELECT a.application_id, a.clinic_id, a.status,
                    p.plan_id, p.plan_key, p.display_name, p.tagline,
                    p.description, p.monthly_amount_minor,
                    p.annual_amount_minor, p.currency, p.is_recommended,
                    p.sort_order, p.entitlements
               FROM clinic_applications a
               JOIN plans p ON p.plan_key = a.selected_plan AND p.active = true
              WHERE a.application_id = $1`,
            [applicationId],
          )
        ).rows[0];
        validateApplicationPaymentTarget(row, { applicationId, clinicId });
        return this.#mapBillingPlan(row);
      },
    );
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
    return this.#initializeCheckout({
      auth,
      clinicId,
      billingCycle,
      callbackUrl:
        this.environment.paymentCallbackUrl ??
        this.environment.PAYSTACK_CALLBACK_URL ??
        this.environment.APP_PAYMENT_CALLBACK_URL,
      loadContext: async (client) => {
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
        return {
          email: billingUser.email,
          planCode,
          paymentScope: 'clinic_subscription',
          auditAction: 'subscription.checkout_started',
        };
      },
    });
  }

  async initializeApplicationCheckout({
    applicationId,
    clinicId,
    billingCycle,
    retry = false,
  }) {
    return this.#initializeCheckout({
      auth: { accountType: 'PlatformOwner' },
      auditAuth: null,
      clinicId,
      billingCycle,
      callbackUrl:
        this.environment.registrationPaymentCallbackUrl ??
        `${this.environment.APP_DEEP_LINK_SCHEME ?? 'avera'}://app/payments/registration-callback`,
      loadContext: async (client) => {
        await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
          `clinic-application-payment:${applicationId}`,
        ]);
        const application = (
          await client.query(
            `SELECT application_id, clinic_id, status, selected_plan,
                    payment_status, payment_reference, administrator_email,
                    application_reference
               FROM clinic_applications
              WHERE application_id = $1
              FOR UPDATE`,
            [applicationId],
          )
        ).rows[0];
        validateApplicationPaymentTarget(application, { applicationId, clinicId });
        if (['Paid', 'TestVerified'].includes(application.payment_status)) {
          throw serviceError(
            'payment_already_verified',
            'Payment has already been verified for this clinic application.',
            409,
          );
        }
        if (application.payment_reference) {
          const previous = (
            await client.query(
              `SELECT status
                 FROM subscription_payment_transactions
                WHERE reference = $1 AND clinic_id = $2`,
              [application.payment_reference, clinicId],
            )
          ).rows[0];
          if (previous?.status === 'Successful') {
            throw serviceError(
              'payment_already_verified',
              'Payment has already been verified for this clinic application.',
              409,
            );
          }
          if (previous?.status === 'Pending' && !retry) {
            throw serviceError(
              'payment_in_progress',
              'A payment checkout is already in progress for this application.',
              409,
            );
          }
          if (previous?.status === 'Pending' && retry) {
            await client.query(
              `UPDATE subscription_payment_transactions
                  SET status = 'Abandoned', updated_at = now(),
                      gateway_response_summary =
                        COALESCE(gateway_response_summary, '{}'::jsonb) ||
                        jsonb_build_object('reason', 'applicant_retry')
                WHERE reference = $1 AND clinic_id = $2 AND status = 'Pending'`,
              [application.payment_reference, clinicId],
            );
          }
        }
        return {
          email: application.administrator_email,
          planCode: application.selected_plan,
          paymentScope: 'clinic_application',
          applicationId,
          applicationReference: application.application_reference,
          auditAction: 'clinic.application_payment_started',
          afterInsert: async (reference) => {
            await client.query(
              `UPDATE clinic_applications
                  SET payment_reference = $2, payment_status = 'Pending',
                      updated_at = now()
                WHERE application_id = $1`,
              [applicationId, reference],
            );
          },
        };
      },
    });
  }

  async #initializeCheckout({
    auth,
    auditAuth = auth,
    clinicId,
    billingCycle,
    callbackUrl,
    loadContext,
  }) {
    this.#paymentMode();
    const cycle = normalizeCycle(billingCycle);
    const result = await withTenantTransaction(
      this.pool,
      tenantContext(auth, clinicId),
      async (client) => {
        const context = await loadContext(client);
        const plan = (
          await client.query(
            `SELECT plan_key, display_name, monthly_amount_minor,
                    annual_amount_minor, currency
               FROM plans
              WHERE plan_key = $1 AND active = true`,
            [context.planCode],
          )
        ).rows[0];
        if (!plan) {
          throw serviceError(
            'invalid_plan',
            'The selected plan is unavailable.',
            400,
          );
        }
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
        if (amountMinor == null || !gatewayPlanCode) {
          throw serviceError(
            'plan_not_configured',
            `${plan.display_name} ${cycle} billing has not been configured.`,
            409,
          );
        }
        if (!this.gateway.configured) {
          throw serviceError(
            this.gateway.configurationError ?? 'gateway_not_configured',
            'Paystack payment configuration is unavailable.',
            503,
          );
        }
        const reference = createPaymentReference();
        const metadata = {
          clinicId,
          planCode: plan.plan_key,
          billingCycle: cycle,
          paymentScope: context.paymentScope,
          ...(context.applicationId && context.email
            ? { accountEmail: String(context.email).trim().toLowerCase() }
            : {}),
          ...(context.applicationId
            ? { applicationId: context.applicationId }
            : {}),
          ...(context.applicationReference
            ? { applicationReference: context.applicationReference }
            : {}),
        };
        await client.query(
          `INSERT INTO subscription_payment_transactions
             (clinic_id, reference, gateway, plan_code, billing_cycle,
              amount_minor, currency, status, gateway_response_summary)
           VALUES ($1, $2, 'paystack', $3, $4, $5, $6, 'Pending', $7::jsonb)`,
          [
            clinicId,
            reference,
            plan.plan_key,
            cycle,
            Number(amountMinor),
            plan.currency,
            JSON.stringify(metadata),
          ],
        );
        await context.afterInsert?.(reference);
        await audit(client, {
          clinicId,
          auth: auditAuth,
          action: context.auditAction,
          targetId: context.applicationId ?? null,
          next: { reference, planCode: plan.plan_key, billingCycle: cycle },
        });
        return {
          email: context.email,
          amountMinor: Number(amountMinor),
          currency: plan.currency,
          gatewayPlanCode,
          reference,
          metadata,
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
        callbackUrl,
        metadata: result.metadata,
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
                gateway_response_summary =
                  COALESCE(gateway_response_summary, '{}'::jsonb) ||
                  jsonb_build_object('reason', $2::text)
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

  async verifyConfiguredPayment(reference, auth = null) {
    return this.#paymentMode() === 'test'
      ? this.verifyOnly(reference, auth)
      : this.verifyAndApply(reference, auth);
  }

  async verifyOnly(reference, auth = null) {
    return this.#verifyWithoutApplying({
      reference,
      auth,
      mode: 'test',
    });
  }

  async verifyApplicationPayment({ applicationId, clinicId, reference }) {
    const application = await withTenantTransaction(
      this.pool,
      { isPlatformOwner: true },
      async (client) => (
        await client.query(
          `SELECT application_id, clinic_id, status, selected_plan,
                  payment_status, payment_reference, application_reference,
                  administrator_email
             FROM clinic_applications
            WHERE application_id = $1`,
          [applicationId],
        )
      ).rows[0],
    );
    validateApplicationPaymentTarget(application, { applicationId, clinicId });
    let preferredError;
    try {
      return await this.#verifyApplicationPaymentReference({
        applicationId,
        clinicId,
        reference,
      });
    } catch (error) {
      if (!isRecoverableApplicationPaymentError(error)) throw error;
      preferredError = error;
    }

    const alternatives = (
      await this.pool.query(
        `SELECT reference
           FROM subscription_payment_transactions
          WHERE clinic_id = $1
            AND reference <> $2
            AND gateway_response_summary->>'paymentScope' = 'clinic_application'
            AND gateway_response_summary->>'applicationId' = $3
          ORDER BY (status = 'Successful') DESC, created_at DESC
          LIMIT 10`,
        [clinicId, reference, applicationId],
      )
    ).rows;
    for (const candidate of alternatives) {
      try {
        return await this.#verifyApplicationPaymentReference({
          applicationId,
          clinicId,
          reference: candidate.reference,
        });
      } catch (error) {
        if (!isRecoverableApplicationPaymentError(error)) throw error;
      }
    }
    throw preferredError;
  }

  async #verifyApplicationPaymentReference({
    applicationId,
    clinicId,
    reference,
  }) {
    const expected = (
      await this.pool.query(
        `SELECT clinic_id, plan_code, gateway_response_summary
           FROM subscription_payment_transactions
          WHERE reference = $1`,
        [reference],
      )
    ).rows[0];
    const paymentMetadata = normalizeMetadata(expected?.gateway_response_summary);
    if (
      expected?.clinic_id !== clinicId ||
      paymentMetadata.paymentScope !== 'clinic_application' ||
      paymentMetadata.applicationId !== applicationId
    ) {
      throw serviceError(
        'payment_application_mismatch',
        'This payment does not match the clinic application.',
        403,
      );
    }
    const mode = this.#paymentMode();
    const verification = await this.#verifyWithoutApplying({
      reference,
      auth: { clinicId, accountType: 'ClinicApplication' },
      mode,
      afterVerified: async (client, payment) => {
        const lockedApplication = (
          await client.query(
            `SELECT application_id, clinic_id, status, selected_plan,
                    payment_status, payment_reference, application_reference,
                    administrator_email
               FROM clinic_applications
              WHERE application_id = $1
              FOR UPDATE`,
            [applicationId],
          )
        ).rows[0];
        validateApplicationPaymentTarget(lockedApplication, {
          applicationId,
          clinicId,
        });
        const verifiedMetadata = normalizeMetadata(
          payment.gateway_response_summary,
        );
        const checkoutEmail = normalizeEmail(
          verifiedMetadata.accountEmail ?? verifiedMetadata.payerEmail,
        );
        const currentEmail = normalizeEmail(
          lockedApplication.administrator_email,
        );
        const registrationIdentityChanged = Boolean(
          checkoutEmail && currentEmail && checkoutEmail !== currentEmail,
        );
        const paymentStatus = mode === 'test' ? 'TestVerified' : 'Paid';
        await client.query(
          `UPDATE clinic_applications
              SET payment_status = $2, status = 'Pending',
                  payment_reference = $3, selected_plan = $4,
                  updated_at = now()
            WHERE application_id = $1`,
          [applicationId, paymentStatus, reference, expected.plan_code],
        );
        await client.query(
          `UPDATE clinics
              SET status = CASE
                    WHEN status IN ('RegistrationDraft', 'Pending', 'PendingApproval')
                      THEN 'PendingApproval'
                    ELSE status
                  END,
                  subscription_plan = $2, updated_at = now(),
                  revision = revision + 1
            WHERE clinic_id = $1`,
          [clinicId, expected.plan_code],
        );
        await audit(client, {
          clinicId,
          auth: null,
          action: 'clinic.application_payment_verified',
          targetId: applicationId,
          next: {
            reference,
            paymentStatus,
            mode,
            planCode: expected.plan_code,
            reconciledReference:
              lockedApplication.payment_reference !== reference,
            registrationIdentityChanged,
          },
        });
        return {
          application: {
            applicationId,
            clinicId,
            reference: lockedApplication.application_reference,
            status: 'Pending',
            paymentStatus,
            registrationIdentityChanged,
          },
        };
      },
    });
    let approval;
    let approvalIssue;
    if (verification.application?.registrationIdentityChanged) {
      approvalIssue = {
        code: 'registration_identity_changed_after_checkout',
        message: 'Payment is verified, but the Account Email changed after Paystack checkout. Platform Owner review is required before administrator activation.',
        requiresPlatformOwner: true,
      };
    } else {
      try {
        approval = await this.onApplicationPaymentVerified?.({
          applicationId,
          clinicId,
          reference,
          mode,
        });
      } catch (error) {
        approvalIssue = safeApplicationApprovalIssue(error);
      }
    }
    return {
      ...verification,
      applicationApproved: approval?.approved === true,
      activation: safeActivationSummary(approval?.activation),
      approvalIssue,
    };
  }

  async #verifyWithoutApplying({
    reference,
    auth,
    mode,
    afterVerified,
  }) {
    const { expected, verified, alreadySuccessful } =
      await this.#verifyExpectedPayment(reference, auth, mode);
    if (alreadySuccessful && afterVerified == null) {
      return this.#verificationOnlyResult(expected, mode);
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
        let payment = locked;
        if (locked.status !== 'Successful') {
          const paidAt = verified.paid_at
            ? new Date(verified.paid_at)
            : new Date();
          const summary = {
            ...normalizeMetadata(locked.gateway_response_summary),
            gatewayStatus: verified.status,
            mode,
            subscriptionApplied: false,
            ...(normalizeEmail(verified.customer?.email)
              ? { payerEmail: normalizeEmail(verified.customer.email) }
              : {}),
          };
          payment = (
            await client.query(
              `UPDATE subscription_payment_transactions
                  SET status = 'Successful', payment_channel = $2,
                      gateway_transaction_id = $3, paid_at = $4,
                      updated_at = now(), gateway_response_summary = $5::jsonb
                WHERE reference = $1 RETURNING *`,
              [
                reference,
                verified.channel ?? null,
                verified.id == null ? null : String(verified.id),
                paidAt,
                JSON.stringify(summary),
              ],
            )
          ).rows[0] ?? {
            ...locked,
            status: 'Successful',
            payment_channel: verified.channel ?? null,
            gateway_transaction_id:
              verified.id == null ? null : String(verified.id),
            paid_at: paidAt,
            gateway_response_summary: summary,
          };
        }
        const context = await afterVerified?.(client, payment) ?? {};
        return {
          ...this.#verificationOnlyResult(payment, mode),
          ...context,
        };
      },
    );
  }

  async verifyAndApply(reference, auth = null) {
    const { expected, verified, alreadySuccessful } =
      await this.#verifyExpectedPayment(reference, auth, 'live');
    if (alreadySuccessful) return this.#verificationResult(expected);
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
          verified: true,
          mode: 'live',
          subscriptionApplied: true,
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
    const mode = this.#paymentMode();
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
        await this.#verifyWebhookPayment(event.data.reference, mode);
      } else if (mode === 'live') {
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
              gateway_response_summary =
                COALESCE(gateway_response_summary, '{}'::jsonb) || $2::jsonb
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

  async #verifyWebhookPayment(reference, mode) {
    const payment = (
      await this.pool.query(
        `SELECT clinic_id, gateway_response_summary
           FROM subscription_payment_transactions
          WHERE reference = $1`,
        [reference],
      )
    ).rows[0];
    const metadata = normalizeMetadata(payment?.gateway_response_summary);
    if (
      metadata.paymentScope === 'clinic_application' &&
      typeof metadata.applicationId === 'string'
    ) {
      await this.verifyApplicationPayment({
        applicationId: metadata.applicationId,
        clinicId: payment.clinic_id,
        reference,
      });
      return;
    }
    if (mode === 'test') await this.verifyOnly(reference);
    else await this.verifyAndApply(reference);
  }

  async #verifyExpectedPayment(reference, auth, mode) {
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
      const summary = normalizeMetadata(expected.gateway_response_summary);
      const storedMode = summary.mode ??
        (expected.subscription_id != null ? 'live' : null);
      if (storedMode && storedMode !== mode) {
        throw serviceError(
          'payment_mode_mismatch',
          'The payment mode does not match this environment.',
          409,
        );
      }
      return { expected, verified: null, alreadySuccessful: true };
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
    const verificationError =
      validateVerifiedPayment(expected, verified) ??
      validatePaystackDomain(mode, verified?.domain);
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
    return { expected, verified, alreadySuccessful: false };
  }

  async #verificationResult(payment) {
    const subscription = await this.getClinicSubscription(
      { clinicId: payment.clinic_id, accountType: 'PlatformOwner' },
      payment.clinic_id,
    );
    return {
      payment: mapPayment(payment),
      subscription,
      verified: true,
      mode: 'live',
      subscriptionApplied: true,
    };
  }

  #verificationOnlyResult(payment, mode = 'test') {
    return {
      payment: mapPayment(payment),
      subscription: null,
      verified: true,
      mode,
      subscriptionApplied: false,
    };
  }

  #paymentMode() {
    const mode = this.environment.PAYSTACK_MODE;
    if (mode !== 'test' && mode !== 'live') {
      throw serviceError(
        'payment_mode_not_configured',
        'Paystack payment mode has not been configured.',
        503,
      );
    }
    return mode;
  }

  #configuredPlanCode(planKey, billingCycle) {
    const normalized = String(planKey).toUpperCase();
    const cycle = normalizeCycle(billingCycle).toUpperCase();
    return this.environment[`PAYSTACK_${normalized}_${cycle}_PLAN_CODE`] ?? null;
  }

  #mapBillingPlan(row) {
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
  }
}

function safeActivationSummary(activation) {
  if (!activation || typeof activation !== 'object') return null;
  return {
    status: activation.status ?? null,
    deliveryMethod: activation.deliveryMethod ?? null,
    expiresAt: activation.expiresAt ?? null,
  };
}

function isRecoverableApplicationPaymentError(error) {
  return new Set([
    'gateway_request_failed',
    'payment_not_found',
    'payment_not_successful',
    'payment_pending',
  ]).has(error?.code);
}

function safeApplicationApprovalIssue(error) {
  const messages = {
    administrator_identity_conflict:
      'Payment is verified, but the Account Email belongs to another AVERA account. Platform Owner repair is required.',
    administrator_account_email_missing:
      'Payment is verified, but the registration has no valid Account Email for administrator activation.',
    administrator_name_missing:
      'Payment is verified, but the registration has no administrator name for activation.',
    automatic_approval_not_allowed:
      'Payment is verified, but this clinic requires Platform Owner review before activation.',
  };
  const code = Object.hasOwn(messages, error?.code)
    ? error.code
    : 'administrator_activation_requires_review';
  return {
    code,
    message:
      messages[code] ??
      'Payment is verified, but administrator activation requires Platform Owner review.',
    requiresPlatformOwner: true,
  };
}

function normalizeEmail(value) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim().toLowerCase();
  return normalized.length > 0 ? normalized : null;
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

export function validatePaystackDomain(mode, domain) {
  if (domain == null) return null;
  const normalized = String(domain).toLowerCase();
  if (normalized !== 'test' && normalized !== 'live') {
    return 'payment_domain_invalid';
  }
  return normalized === mode ? null : 'payment_mode_mismatch';
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

function validateApplicationPaymentTarget(
  application,
  { applicationId, clinicId },
) {
  if (
    !application ||
    application.application_id !== applicationId ||
    application.clinic_id !== clinicId
  ) {
    throw serviceError(
      'clinic_application_not_found',
      'The clinic application could not be found.',
      404,
    );
  }
  if (!['AwaitingPayment', 'Pending', 'PendingApproval', 'Approved'].includes(application.status)) {
    throw serviceError(
      'clinic_application_payment_unavailable',
      'Payment is not available for this clinic application.',
      409,
    );
  }
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
