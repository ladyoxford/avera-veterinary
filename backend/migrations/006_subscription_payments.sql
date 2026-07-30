ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS tagline TEXT,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS monthly_amount_minor BIGINT,
  ADD COLUMN IF NOT EXISTS annual_amount_minor BIGINT,
  ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'NGN',
  ADD COLUMN IF NOT EXISTS paystack_monthly_plan_code TEXT,
  ADD COLUMN IF NOT EXISTS paystack_annual_plan_code TEXT,
  ADD COLUMN IF NOT EXISTS is_recommended BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS entitlements JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE plans
  ADD CONSTRAINT plans_monthly_amount_nonnegative
    CHECK (monthly_amount_minor IS NULL OR monthly_amount_minor >= 0),
  ADD CONSTRAINT plans_annual_amount_nonnegative
    CHECK (annual_amount_minor IS NULL OR annual_amount_minor >= 0);

INSERT INTO plans (
  plan_key, display_name, tagline, description, is_recommended, sort_order
) VALUES
  ('Starter', 'Starter', 'Digital clinic management.',
   'Core digital records and practice workflows.', false, 10),
  ('Professional', 'Professional',
   'Digital clinic management with an AI clinical assistant.',
   'Advanced clinical workflows, analytics and Vera capabilities.', true, 20),
  ('Enterprise', 'Enterprise',
   'AI-powered veterinary hospital operating system.',
   'Multi-clinic operations, integrations and enterprise intelligence.', false, 30)
ON CONFLICT (plan_key) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  tagline = EXCLUDED.tagline,
  description = EXCLUDED.description,
  is_recommended = EXCLUDED.is_recommended,
  sort_order = EXCLUDED.sort_order,
  updated_at = now();

ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS billing_cycle TEXT NOT NULL DEFAULT 'monthly',
  ADD COLUMN IF NOT EXISTS gateway TEXT,
  ADD COLUMN IF NOT EXISTS gateway_customer_code TEXT,
  ADD COLUMN IF NOT EXISTS gateway_subscription_code TEXT,
  ADD COLUMN IF NOT EXISTS gateway_email_token TEXT,
  ADD COLUMN IF NOT EXISTS current_period_start TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS next_billing_date TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_one_current_per_clinic_idx
  ON subscriptions (clinic_id)
  WHERE status IN ('Trial', 'Pending Payment', 'Active', 'Past Due', 'Non-renewing');

CREATE TABLE subscription_payment_transactions (
  payment_transaction_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  subscription_id UUID REFERENCES subscriptions(subscription_id),
  reference TEXT NOT NULL UNIQUE,
  gateway TEXT NOT NULL,
  plan_code TEXT NOT NULL,
  billing_cycle TEXT NOT NULL,
  amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),
  currency TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'Pending',
  payment_channel TEXT,
  gateway_transaction_id TEXT,
  gateway_response_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE payment_webhook_events (
  payment_webhook_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway TEXT NOT NULL,
  event_type TEXT NOT NULL,
  event_identity TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  processing_status TEXT NOT NULL DEFAULT 'Received',
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  UNIQUE (gateway, event_identity)
);

CREATE INDEX IF NOT EXISTS subscription_payments_clinic_created_idx
  ON subscription_payment_transactions (clinic_id, created_at DESC);
CREATE INDEX IF NOT EXISTS subscription_payments_subscription_idx
  ON subscription_payment_transactions (subscription_id);

ALTER TABLE subscription_payment_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscription_payment_tenant_policy
  ON subscription_payment_transactions
  USING (
    current_setting('avera.is_platform_owner', true) = 'true'
    OR clinic_id::text = current_setting('avera.clinic_id', true)
  );
