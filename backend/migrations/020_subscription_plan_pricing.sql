UPDATE plans AS plan
SET monthly_amount_minor = pricing.monthly_amount_minor,
    annual_amount_minor = pricing.annual_amount_minor,
    currency = 'NGN',
    updated_at = now()
FROM (
  VALUES
    ('Professional', 500000::BIGINT, 5000000::BIGINT),
    ('Enterprise', 1000000::BIGINT, 10000000::BIGINT)
) AS pricing(plan_key, monthly_amount_minor, annual_amount_minor)
WHERE plan.plan_key = pricing.plan_key;
