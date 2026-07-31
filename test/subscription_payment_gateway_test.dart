import 'dart:convert';

import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/subscription/subscription_payment_gateway.dart';
import 'package:avera/core/subscription/subscription_plan_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

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

  test(
    'checkout initialization alone never marks a subscription successful',
    () async {
      final requests = <http.Request>[];
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      final gateway = PaystackSubscriptionGateway(
        ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/initialize')) {
              return http.Response(
                jsonEncode({
                  'authorizationUrl': 'https://checkout.paystack.test/session',
                  'reference': 'AVERA-TEST-REFERENCE',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'subscription': {
                  'id': 'subscription-1',
                  'clinicId': 'clinic-1',
                  'planCode': 'Professional',
                  'billingCycle': 'monthly',
                  'status': 'Active',
                  'gateway': 'paystack',
                  'updatedAt': '2026-07-31T10:00:00.000Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final checkout = await gateway.initializeCheckout(
        clinicId: 'clinic-1',
        plan: SubscriptionPlan.professional,
        billingCycle: SubscriptionBillingCycle.monthly,
      );

      expect(checkout.reference, 'AVERA-TEST-REFERENCE');
      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/api/v1/subscriptions/payments/paystack/initialize',
      );

      final subscription = await gateway.verifyPayment(checkout.reference);

      expect(requests, hasLength(2));
      expect(
        requests.last.url.path,
        '/api/v1/subscriptions/payments/paystack/verify/AVERA-TEST-REFERENCE',
      );
      expect(subscription?.status, 'Active');
      expect(subscription?.clinicId, 'clinic-1');
    },
  );
}
