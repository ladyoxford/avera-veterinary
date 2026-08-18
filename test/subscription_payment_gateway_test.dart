import 'dart:convert';

import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/subscription/registration_payment_session_store.dart';
import 'package:avera/core/subscription/subscription_payment_gateway.dart';
import 'package:avera/core/subscription/subscription_plan_config.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/administration/screens/subscription_plans_screen.dart';
import 'package:avera/features/authentication/screens/clinic_registration_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  test('test-mode verification DTO is explicit and has no subscription', () {
    final verification = SubscriptionPaymentVerification.fromJson({
      'verified': true,
      'mode': 'test',
      'subscriptionApplied': false,
      'subscription': null,
      'payment': {
        'reference': 'AVERA-TEST-1',
        'planCode': 'Professional',
        'billingCycle': 'monthly',
        'amountMinor': 250000,
        'currency': 'NGN',
        'status': 'Successful',
        'paidAt': '2026-07-31T10:00:00.000Z',
        'createdAt': '2026-07-31T09:59:00.000Z',
      },
    });

    expect(verification.verified, isTrue);
    expect(verification.isTestMode, isTrue);
    expect(verification.subscriptionApplied, isFalse);
    expect(verification.subscription, isNull);
    expect(verification.payment?.status, 'Successful');
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
                'verified': true,
                'mode': 'live',
                'subscriptionApplied': true,
                'payment': {
                  'reference': 'AVERA-TEST-REFERENCE',
                  'planCode': 'Professional',
                  'billingCycle': 'monthly',
                  'amountMinor': 250000,
                  'currency': 'NGN',
                  'status': 'Successful',
                  'createdAt': '2026-07-31T09:59:00.000Z',
                },
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

      final verification = await gateway.verifyPayment(checkout.reference);

      expect(requests, hasLength(2));
      expect(
        requests.last.url.path,
        '/api/v1/subscriptions/payments/paystack/verify/AVERA-TEST-REFERENCE',
      );
      expect(verification.mode, 'live');
      expect(verification.subscriptionApplied, isTrue);
      expect(verification.subscription?.status, 'Active');
      expect(verification.subscription?.clinicId, 'clinic-1');
    },
  );

  test(
    'registration checkout uses scoped public endpoints without session authorization',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final requests = <http.Request>[];
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'signed-in-access-token',
        refreshToken: 'signed-in-refresh-token',
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
                  'authorizationUrl':
                      'https://checkout.paystack.test/application-1',
                  'reference': 'AVERA-APPLICATION-1',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'verified': true,
                'mode': 'test',
                'subscriptionApplied': false,
                'payment': {
                  'reference': 'AVERA-APPLICATION-1',
                  'planCode': 'Enterprise',
                  'billingCycle': 'annual',
                  'amountMinor': 5000000,
                  'currency': 'NGN',
                  'status': 'Successful',
                  'createdAt': '2026-08-18T08:00:00.000Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final checkout = await gateway.initializeRegistrationCheckout(
        applicationId: 'application-1',
        accessToken: 'scoped-registration-capability',
        billingCycle: SubscriptionBillingCycle.annual,
        retry: true,
      );
      final verification = await gateway.verifyRegistrationPayment(
        applicationId: 'application-1',
        accessToken: 'scoped-registration-capability',
        reference: checkout.reference,
      );

      expect(requests, hasLength(2));
      expect(
        requests.first.url.path,
        '/api/v1/clinic-applications/application-1/payments/paystack/initialize',
      );
      expect(jsonDecode(requests.first.body), {
        'accessToken': 'scoped-registration-capability',
        'billingCycle': 'annual',
        'retry': true,
      });
      expect(
        requests.last.url.path,
        '/api/v1/clinic-applications/application-1/payments/paystack/verify',
      );
      expect(jsonDecode(requests.last.body), {
        'accessToken': 'scoped-registration-capability',
        'reference': 'AVERA-APPLICATION-1',
      });
      expect(
        requests.every(
          (request) => !request.headers.keys
              .map((key) => key.toLowerCase())
              .contains('authorization'),
        ),
        isTrue,
      );
      expect(verification.isTestMode, isTrue);
      expect(verification.subscriptionApplied, isFalse);
      expect(verification.subscription, isNull);
    },
  );

  test(
    'registration payment session is encrypted-storage scoped by reference',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = RegistrationPaymentSessionStore(FlutterSecureStorage());
      const session = RegistrationPaymentSession(
        applicationId: 'application-1',
        clinicId: 'clinic-1',
        applicationReference: 'AVR-20260818-ABC123',
        plan: 'Enterprise',
        accessToken: 'scoped-registration-capability',
        paymentReference: 'AVERA-APPLICATION-1',
      );

      await store.save(session);

      expect(
        (await store.loadForReference('AVERA-APPLICATION-1'))?.accessToken,
        'scoped-registration-capability',
      );
      expect(await store.loadForReference('ANOTHER-REFERENCE'), isNull);
      await store.clear();
      expect(await store.loadActive(), isNull);
    },
  );

  testWidgets(
    'registration payment starts for the canonical application without exposing its token',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = RegistrationPaymentSessionStore(FlutterSecureStorage());
      final verification = SubscriptionPaymentVerification.fromJson({
        'verified': true,
        'mode': 'test',
        'subscriptionApplied': false,
        'payment': {
          'reference': 'AVERA-APPLICATION-1',
          'planCode': 'Enterprise',
          'billingCycle': 'monthly',
          'amountMinor': 500000,
          'currency': 'NGN',
          'status': 'Successful',
          'createdAt': '2026-08-18T08:00:00.000Z',
        },
      });
      final gateway = _FakeSubscriptionPaymentGateway(
        verification,
        registrationCheckout: SubscriptionCheckoutSession(
          authorizationUrl: Uri.parse(
            'https://checkout.paystack.test/application-1',
          ),
          reference: 'AVERA-APPLICATION-1',
        ),
      );
      Uri? launched;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionPaymentGatewayProvider.overrideWithValue(gateway),
            registrationPaymentSessionStoreProvider.overrideWithValue(store),
            registrationPaymentCheckoutLauncherProvider.overrideWithValue((
              uri,
            ) async {
              launched = uri;
              return true;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ClinicRegistrationPaymentScreen(
              application: ClinicApplication(
                clinicName: 'Crest Veterinary Hospital',
                clinicEmail: 'hello@crest.test',
                phoneNumber: '+2348000000000',
                address: '1 Veterinary Way',
                city: 'Abuja',
                country: 'Nigeria',
                administratorName: 'Crest Administrator',
                administratorEmail: 'administrator@crest.test',
                administratorPhone: '+2348111111111',
                professionalTitle: 'Veterinarian',
                subscriptionPlan: 'Enterprise',
                applicationId: 'application-1',
                clinicId: 'clinic-1',
                reference: 'AVR-20260818-ABC123',
                paymentStatus: 'Pending',
                paymentAccessToken: 'scoped-registration-capability',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('registration-continue-to-paystack')),
      );
      await tester.pumpAndSettle();

      expect(gateway.registrationInitializationCalls, hasLength(1));
      expect(gateway.registrationInitializationCalls.single, {
        'applicationId': 'application-1',
        'accessToken': 'scoped-registration-capability',
        'billingCycle': 'monthly',
        'retry': false,
      });
      expect(
        launched,
        Uri.parse('https://checkout.paystack.test/application-1'),
      );
      expect(find.text('Pending approval'), findsOneWidget);
      expect(find.text('scoped-registration-capability'), findsNothing);
      expect((await store.loadActive())?.applicationId, 'application-1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled checkout preserves the application and retries only payment',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = RegistrationPaymentSessionStore(FlutterSecureStorage());
      final gateway = _FakeSubscriptionPaymentGateway(
        SubscriptionPaymentVerification.fromJson({
          'verified': false,
          'mode': 'test',
          'subscriptionApplied': false,
        }),
        registrationCheckout: SubscriptionCheckoutSession(
          authorizationUrl: Uri.parse(
            'https://checkout.paystack.test/application-1',
          ),
          reference: 'AVERA-APPLICATION-1',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionPaymentGatewayProvider.overrideWithValue(gateway),
            registrationPaymentSessionStoreProvider.overrideWithValue(store),
            registrationPaymentCheckoutLauncherProvider.overrideWithValue(
              (_) async => false,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ClinicRegistrationPaymentScreen(
              application: ClinicApplication(
                clinicName: 'Crest Veterinary Hospital',
                clinicEmail: 'hello@crest.test',
                phoneNumber: '+2348000000000',
                address: '1 Veterinary Way',
                city: 'Abuja',
                country: 'Nigeria',
                administratorName: 'Crest Administrator',
                administratorEmail: 'administrator@crest.test',
                administratorPhone: '+2348111111111',
                professionalTitle: 'Veterinarian',
                subscriptionPlan: 'Enterprise',
                applicationId: 'application-1',
                clinicId: 'clinic-1',
                reference: 'AVR-20260818-ABC123',
                paymentStatus: 'Pending',
                paymentAccessToken: 'scoped-registration-capability',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('registration-continue-to-paystack')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The secure payment page could not be opened.'),
        findsOneWidget,
      );
      expect(find.text('AVR-20260818-ABC123'), findsOneWidget);
      expect((await store.loadActive())?.applicationId, 'application-1');
      expect(gateway.registrationInitializationCalls, hasLength(1));

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('registration-retry-payment')));
      await tester.pumpAndSettle();

      expect(gateway.registrationInitializationCalls, hasLength(2));
      expect(gateway.registrationInitializationCalls.last['retry'], isTrue);
      expect(find.text('AVR-20260818-ABC123'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration callback verifies from secure state and clears the capability',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = RegistrationPaymentSessionStore(FlutterSecureStorage());
      await store.save(
        const RegistrationPaymentSession(
          applicationId: 'application-1',
          clinicId: 'clinic-1',
          applicationReference: 'AVR-20260818-ABC123',
          plan: 'Enterprise',
          accessToken: 'scoped-registration-capability',
          paymentReference: 'AVERA-APPLICATION-1',
        ),
      );
      final gateway = _FakeSubscriptionPaymentGateway(
        SubscriptionPaymentVerification.fromJson({
          'verified': true,
          'mode': 'live',
          'subscriptionApplied': false,
          'payment': {
            'reference': 'AVERA-APPLICATION-1',
            'planCode': 'Enterprise',
            'billingCycle': 'monthly',
            'amountMinor': 500000,
            'currency': 'NGN',
            'status': 'Successful',
            'createdAt': '2026-08-18T08:00:00.000Z',
          },
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionPaymentGatewayProvider.overrideWithValue(gateway),
            registrationPaymentSessionStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ClinicRegistrationPaymentCallbackScreen(
              reference: 'AVERA-APPLICATION-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.registrationVerificationCalls, [
        {
          'applicationId': 'application-1',
          'accessToken': 'scoped-registration-capability',
          'reference': 'AVERA-APPLICATION-1',
        },
      ]);
      expect(find.text('scoped-registration-capability'), findsNothing);
      expect(
        find.textContaining(
          'Your clinic application remains pending approval.',
        ),
        findsOneWidget,
      );
      expect(await store.loadActive(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'test-mode callback reports verification without refreshing active plan',
    (tester) async {
      var activeSubscriptionLoads = 0;
      final gateway = _FakeSubscriptionPaymentGateway(
        SubscriptionPaymentVerification.fromJson({
          'verified': true,
          'mode': 'test',
          'subscriptionApplied': false,
          'payment': {
            'reference': 'AVERA-TEST-REFERENCE',
            'planCode': 'Professional',
            'billingCycle': 'monthly',
            'amountMinor': 250000,
            'currency': 'NGN',
            'status': 'Successful',
            'createdAt': '2026-07-31T09:59:00.000Z',
          },
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionPaymentGatewayProvider.overrideWithValue(gateway),
            activeClinicSubscriptionProvider.overrideWith((ref) async {
              activeSubscriptionLoads += 1;
              return null;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Consumer(
              builder: (context, ref, child) {
                ref.watch(activeClinicSubscriptionProvider);
                return child!;
              },
              child: const SubscriptionPaymentCallbackScreen(
                reference: 'AVERA-TEST-REFERENCE',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Payment verified successfully in test mode.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No subscription changes were applied.'),
        findsOneWidget,
      );
      expect(find.textContaining('upgraded'), findsNothing);
      expect(gateway.verifiedReferences, ['AVERA-TEST-REFERENCE']);
      expect(activeSubscriptionLoads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeSubscriptionPaymentGateway implements SubscriptionPaymentGateway {
  _FakeSubscriptionPaymentGateway(
    this.verification, {
    this.registrationCheckout,
  });

  final SubscriptionPaymentVerification verification;
  final SubscriptionCheckoutSession? registrationCheckout;
  final List<String> verifiedReferences = [];
  final List<Map<String, Object?>> registrationInitializationCalls = [];
  final List<Map<String, String>> registrationVerificationCalls = [];

  @override
  Future<SubscriptionPaymentVerification> verifyPayment(
    String reference,
  ) async {
    verifiedReferences.add(reference);
    return verification;
  }

  @override
  Future<List<SubscriptionBillingPlan>> loadPlans() =>
      throw UnimplementedError();

  @override
  Future<ServerClinicSubscription?> loadSubscription(String clinicId) =>
      throw UnimplementedError();

  @override
  Future<List<SubscriptionPaymentRecord>> loadPayments(String clinicId) =>
      throw UnimplementedError();

  @override
  Future<SubscriptionCheckoutSession> initializeCheckout({
    required String clinicId,
    required SubscriptionPlan plan,
    required SubscriptionBillingCycle billingCycle,
  }) => throw UnimplementedError();

  @override
  Future<SubscriptionCheckoutSession> initializeRegistrationCheckout({
    required String applicationId,
    required String accessToken,
    required SubscriptionBillingCycle billingCycle,
    bool retry = false,
  }) async {
    registrationInitializationCalls.add({
      'applicationId': applicationId,
      'accessToken': accessToken,
      'billingCycle': billingCycle.apiValue,
      'retry': retry,
    });
    return registrationCheckout ?? (throw UnimplementedError());
  }

  @override
  Future<SubscriptionPaymentVerification> verifyRegistrationPayment({
    required String applicationId,
    required String accessToken,
    required String reference,
  }) async {
    registrationVerificationCalls.add({
      'applicationId': applicationId,
      'accessToken': accessToken,
      'reference': reference,
    });
    return verification;
  }

  @override
  Future<ServerClinicSubscription> cancelRenewal(String clinicId) =>
      throw UnimplementedError();

  @override
  Future<ServerClinicSubscription> reactivateSubscription(String clinicId) =>
      throw UnimplementedError();
}
