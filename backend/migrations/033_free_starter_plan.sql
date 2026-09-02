-- Starter is AVERA's canonical payment-free plan. A zero amount is distinct
-- from NULL, which continues to mean that paid checkout pricing is unconfigured.
UPDATE plans
   SET monthly_amount_minor = 0,
       annual_amount_minor = 0,
       currency = 'NGN',
       updated_at = now()
 WHERE plan_key = 'Starter';
