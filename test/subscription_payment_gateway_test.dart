import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/subscription/subscription_payment_gateway.dart';
import 'package:avera/core/subscription/subscription_plan_config.dart';

void main() {
  test('server plan DTO preserves nullable unconfigured prices', () {
    final plan = SubscriptionBillingPlan.fromJson({
      'code': 'Professional',
      'name': 'Professional',
      'tagline': 'Digital clinic management with an AI clinical assistant.',
      'currency': 'NGN',
      'monthlyAmountMinor': null,
      'annualAmountMinor': null,
      'monthlyCheckoutConfigured': false,
      'annualCheckoutConfigured': false,
    });

    expect(plan.plan, SubscriptionPlan.professional);
    expect(plan.monthlyAmountMinor, isNull);
    expect(
      plan.checkoutConfiguredFor(SubscriptionBillingCycle.monthly),
      isFalse,
    );
  });

  test('payment DTO parses plan, cycle, amount and dates safely', () {
    final payment = SubscriptionPaymentRecord.fromJson({
      'reference': 'AVERA-TEST-1',
      'planCode': 'Enterprise',
      'billingCycle': 'annual',
      'amountMinor': 123400,
      'currency': 'NGN',
      'status': 'Successful',
      'paidAt': '2026-07-27T10:00:00.000Z',
      'createdAt': '2026-07-27T09:59:00.000Z',
    });

    expect(payment.plan, SubscriptionPlan.enterprise);
    expect(payment.billingCycle, SubscriptionBillingCycle.annual);
    expect(payment.amountMinor, 123400);
    expect(payment.paidAt, isNotNull);
  });

  test('unconfigured gateway exposes all plans without fake prices', () async {
    const gateway = UnconfiguredSubscriptionPaymentGateway();
    final plans = await gateway.loadPlans();

    expect(plans.map((plan) => plan.plan), SubscriptionPlan.values);
    expect(plans.every((plan) => plan.monthlyAmountMinor == null), isTrue);
    expect(
      plans.every(
        (plan) => !plan.checkoutConfiguredFor(SubscriptionBillingCycle.monthly),
      ),
      isTrue,
    );
  });
}
