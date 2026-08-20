import '../remote/api_client.dart';
import 'subscription_plan_config.dart';
import 'package:intl/intl.dart';

enum SubscriptionBillingCycle {
  monthly,
  annual;

  String get apiValue => name;
}

String formatSubscriptionAmount({
  required int amountMinor,
  required String currency,
}) {
  final amount = amountMinor / 100;
  if (currency.toUpperCase() == 'NGN') {
    return '₦${NumberFormat.decimalPattern().format(amount)}';
  }
  return NumberFormat.simpleCurrency(
    name: currency,
    decimalDigits: 0,
  ).format(amount);
}

class SubscriptionBillingPlan {
  const SubscriptionBillingPlan({
    required this.plan,
    required this.name,
    required this.tagline,
    required this.currency,
    required this.monthlyAmountMinor,
    required this.annualAmountMinor,
    required this.monthlyCheckoutConfigured,
    required this.annualCheckoutConfigured,
  });

  final SubscriptionPlan plan;
  final String name;
  final String tagline;
  final String currency;
  final int? monthlyAmountMinor;
  final int? annualAmountMinor;
  final bool monthlyCheckoutConfigured;
  final bool annualCheckoutConfigured;

  int? amountFor(SubscriptionBillingCycle cycle) =>
      cycle == SubscriptionBillingCycle.monthly
      ? monthlyAmountMinor
      : annualAmountMinor;

  bool checkoutConfiguredFor(SubscriptionBillingCycle cycle) =>
      cycle == SubscriptionBillingCycle.monthly
      ? monthlyCheckoutConfigured
      : annualCheckoutConfigured;

  factory SubscriptionBillingPlan.fromJson(Map<String, dynamic> json) {
    final plan = SubscriptionPlan.fromStorage(json['code'] as String? ?? '');
    return SubscriptionBillingPlan(
      plan: plan,
      name: json['name'] as String? ?? plan.label,
      tagline:
          json['tagline'] as String? ??
          SubscriptionPlanCatalogue.plan(plan).tagline,
      currency: json['currency'] as String? ?? 'NGN',
      monthlyAmountMinor: (json['monthlyAmountMinor'] as num?)?.toInt(),
      annualAmountMinor: (json['annualAmountMinor'] as num?)?.toInt(),
      monthlyCheckoutConfigured:
          json['monthlyCheckoutConfigured'] as bool? ?? false,
      annualCheckoutConfigured:
          json['annualCheckoutConfigured'] as bool? ?? false,
    );
  }
}

class ServerClinicSubscription {
  const ServerClinicSubscription({
    required this.id,
    required this.clinicId,
    required this.plan,
    required this.billingCycle,
    required this.status,
    required this.gateway,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.nextBillingDate,
    required this.cancelAtPeriodEnd,
    required this.updatedAt,
  });

  final String id;
  final String clinicId;
  final SubscriptionPlan plan;
  final SubscriptionBillingCycle billingCycle;
  final String status;
  final String? gateway;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? nextBillingDate;
  final bool cancelAtPeriodEnd;
  final DateTime updatedAt;

  factory ServerClinicSubscription.fromJson(Map<String, dynamic> json) =>
      ServerClinicSubscription(
        id: json['id'] as String,
        clinicId: json['clinicId'] as String,
        plan: SubscriptionPlan.fromStorage(json['planCode'] as String? ?? ''),
        billingCycle: json['billingCycle'] == 'annual'
            ? SubscriptionBillingCycle.annual
            : SubscriptionBillingCycle.monthly,
        status: json['status'] as String? ?? 'Pending Payment',
        gateway: json['gateway'] as String?,
        currentPeriodStart: _date(json['currentPeriodStart']),
        currentPeriodEnd: _date(json['currentPeriodEnd']),
        nextBillingDate: _date(json['nextBillingDate']),
        cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
        updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
      );
}

class SubscriptionPaymentRecord {
  const SubscriptionPaymentRecord({
    required this.reference,
    required this.plan,
    required this.billingCycle,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.paidAt,
    required this.createdAt,
  });

  final String reference;
  final SubscriptionPlan plan;
  final SubscriptionBillingCycle billingCycle;
  final int amountMinor;
  final String currency;
  final String status;
  final DateTime? paidAt;
  final DateTime createdAt;

  factory SubscriptionPaymentRecord.fromJson(Map<String, dynamic> json) =>
      SubscriptionPaymentRecord(
        reference: json['reference'] as String,
        plan: SubscriptionPlan.fromStorage(json['planCode'] as String? ?? ''),
        billingCycle: json['billingCycle'] == 'annual'
            ? SubscriptionBillingCycle.annual
            : SubscriptionBillingCycle.monthly,
        amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
        currency: json['currency'] as String? ?? 'NGN',
        status: json['status'] as String? ?? 'Pending',
        paidAt: _date(json['paidAt']),
        createdAt:
            _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class SubscriptionPaymentVerification {
  const SubscriptionPaymentVerification({
    required this.payment,
    required this.subscription,
    required this.verified,
    required this.mode,
    required this.subscriptionApplied,
    this.applicationApproved = false,
    this.activationDeliveryMethod,
  });

  final SubscriptionPaymentRecord? payment;
  final ServerClinicSubscription? subscription;
  final bool verified;
  final String mode;
  final bool subscriptionApplied;
  final bool applicationApproved;
  final String? activationDeliveryMethod;

  bool get isTestMode => mode == 'test';

  factory SubscriptionPaymentVerification.fromJson(Map<String, dynamic> json) {
    final paymentValue = json['payment'];
    final subscriptionValue = json['subscription'];
    final payment = paymentValue is Map<String, dynamic>
        ? SubscriptionPaymentRecord.fromJson(paymentValue)
        : null;
    final subscription = subscriptionValue is Map<String, dynamic>
        ? ServerClinicSubscription.fromJson(subscriptionValue)
        : null;
    final subscriptionApplied =
        json['subscriptionApplied'] as bool? ?? subscription != null;
    return SubscriptionPaymentVerification(
      payment: payment,
      subscription: subscription,
      verified:
          json['verified'] as bool? ??
          subscription != null || payment?.status.toLowerCase() == 'successful',
      mode:
          json['mode'] as String? ?? (subscriptionApplied ? 'live' : 'unknown'),
      subscriptionApplied: subscriptionApplied,
      applicationApproved: json['applicationApproved'] as bool? ?? false,
      activationDeliveryMethod:
          (json['activation'] as Map<String, dynamic>?)?['deliveryMethod']
              as String?,
    );
  }
}

class SubscriptionCheckoutSession {
  const SubscriptionCheckoutSession({
    required this.authorizationUrl,
    required this.reference,
  });

  final Uri authorizationUrl;
  final String reference;
}

class SubscriptionBillingSnapshot {
  const SubscriptionBillingSnapshot({
    required this.plans,
    required this.subscription,
    required this.payments,
    required this.isServerAuthoritative,
  });

  final List<SubscriptionBillingPlan> plans;
  final ServerClinicSubscription? subscription;
  final List<SubscriptionPaymentRecord> payments;
  final bool isServerAuthoritative;
}

abstract interface class SubscriptionPaymentGateway {
  Future<List<SubscriptionBillingPlan>> loadPlans();
  Future<SubscriptionBillingPlan> loadRegistrationPaymentPlan({
    required String applicationId,
    required String accessToken,
  });
  Future<ServerClinicSubscription?> loadSubscription(String clinicId);
  Future<List<SubscriptionPaymentRecord>> loadPayments(String clinicId);
  Future<SubscriptionCheckoutSession> initializeCheckout({
    required String clinicId,
    required SubscriptionPlan plan,
    required SubscriptionBillingCycle billingCycle,
  });
  Future<SubscriptionCheckoutSession> initializeRegistrationCheckout({
    required String applicationId,
    required String accessToken,
    required SubscriptionBillingCycle billingCycle,
    bool retry = false,
  });
  Future<SubscriptionPaymentVerification> verifyPayment(String reference);
  Future<SubscriptionPaymentVerification> verifyRegistrationPayment({
    required String applicationId,
    required String accessToken,
    required String reference,
  });
  Future<ServerClinicSubscription> cancelRenewal(String clinicId);
  Future<ServerClinicSubscription> reactivateSubscription(String clinicId);
}

class PaystackSubscriptionGateway implements SubscriptionPaymentGateway {
  const PaystackSubscriptionGateway(this._client);

  final ApiClient _client;

  @override
  Future<List<SubscriptionBillingPlan>> loadPlans() async {
    final response = await _client.get('/api/subscription/plans');
    return (response['plans'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              SubscriptionBillingPlan.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<SubscriptionBillingPlan> loadRegistrationPaymentPlan({
    required String applicationId,
    required String accessToken,
  }) async {
    final response = await _client.post(
      '/api/v1/clinic-applications/${Uri.encodeComponent(applicationId)}/payments/plan',
      body: {'accessToken': accessToken},
    );
    return SubscriptionBillingPlan.fromJson(
      response['plan'] as Map<String, dynamic>,
    );
  }

  @override
  Future<ServerClinicSubscription?> loadSubscription(String clinicId) async {
    final response = await _client.get(
      '/api/clinics/${Uri.encodeComponent(clinicId)}/subscription',
    );
    final value = response['subscription'];
    return value is Map<String, dynamic>
        ? ServerClinicSubscription.fromJson(value)
        : null;
  }

  @override
  Future<List<SubscriptionPaymentRecord>> loadPayments(String clinicId) async {
    final response = await _client.get(
      '/api/clinics/${Uri.encodeComponent(clinicId)}/subscription/payments',
    );
    return (response['payments'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              SubscriptionPaymentRecord.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  @override
  Future<SubscriptionCheckoutSession> initializeCheckout({
    required String clinicId,
    required SubscriptionPlan plan,
    required SubscriptionBillingCycle billingCycle,
  }) async {
    final response = await _client.post(
      '/api/v1/subscriptions/payments/paystack/initialize',
      authenticated: true,
      body: {
        'clinicId': clinicId,
        'planCode': plan.label,
        'billingCycle': billingCycle.apiValue,
      },
    );
    return SubscriptionCheckoutSession(
      authorizationUrl: Uri.parse(response['authorizationUrl'] as String),
      reference: response['reference'] as String,
    );
  }

  @override
  Future<SubscriptionPaymentVerification> verifyPayment(
    String reference,
  ) async {
    final response = await _client.get(
      '/api/v1/subscriptions/payments/paystack/verify/${Uri.encodeComponent(reference)}',
    );
    return SubscriptionPaymentVerification.fromJson(response);
  }

  @override
  Future<SubscriptionCheckoutSession> initializeRegistrationCheckout({
    required String applicationId,
    required String accessToken,
    required SubscriptionBillingCycle billingCycle,
    bool retry = false,
  }) async {
    final response = await _client.post(
      '/api/v1/clinic-applications/${Uri.encodeComponent(applicationId)}/payments/paystack/initialize',
      body: {
        'accessToken': accessToken,
        'billingCycle': billingCycle.apiValue,
        'retry': retry,
      },
    );
    return SubscriptionCheckoutSession(
      authorizationUrl: Uri.parse(response['authorizationUrl'] as String),
      reference: response['reference'] as String,
    );
  }

  @override
  Future<SubscriptionPaymentVerification> verifyRegistrationPayment({
    required String applicationId,
    required String accessToken,
    required String reference,
  }) async {
    final response = await _client.post(
      '/api/v1/clinic-applications/${Uri.encodeComponent(applicationId)}/payments/paystack/verify',
      body: {'accessToken': accessToken, 'reference': reference},
    );
    return SubscriptionPaymentVerification.fromJson(response);
  }

  @override
  Future<ServerClinicSubscription> cancelRenewal(String clinicId) async {
    final response = await _client.post(
      '/api/clinics/${Uri.encodeComponent(clinicId)}/subscription/cancel-renewal',
      authenticated: true,
    );
    return ServerClinicSubscription.fromJson(
      response['subscription'] as Map<String, dynamic>,
    );
  }

  @override
  Future<ServerClinicSubscription> reactivateSubscription(
    String clinicId,
  ) async {
    final response = await _client.post(
      '/api/clinics/${Uri.encodeComponent(clinicId)}/subscription/reactivate',
      authenticated: true,
    );
    return ServerClinicSubscription.fromJson(
      response['subscription'] as Map<String, dynamic>,
    );
  }
}

class UnconfiguredSubscriptionPaymentGateway
    implements SubscriptionPaymentGateway {
  const UnconfiguredSubscriptionPaymentGateway();

  @override
  Future<List<SubscriptionBillingPlan>> loadPlans() async => SubscriptionPlan
      .values
      .map(
        (plan) => SubscriptionBillingPlan(
          plan: plan,
          name: plan.label,
          tagline: SubscriptionPlanCatalogue.plan(plan).tagline,
          currency: 'NGN',
          monthlyAmountMinor: null,
          annualAmountMinor: null,
          monthlyCheckoutConfigured: false,
          annualCheckoutConfigured: false,
        ),
      )
      .toList(growable: false);

  @override
  Future<SubscriptionBillingPlan> loadRegistrationPaymentPlan({
    required String applicationId,
    required String accessToken,
  }) async => _unavailable();

  @override
  Future<ServerClinicSubscription?> loadSubscription(String clinicId) async =>
      null;

  @override
  Future<List<SubscriptionPaymentRecord>> loadPayments(String clinicId) async =>
      const [];

  Never _unavailable() => throw const ApiException(
    'backend_not_configured',
    'Online subscription payments are not configured in local mode.',
  );

  @override
  Future<SubscriptionCheckoutSession> initializeCheckout({
    required String clinicId,
    required SubscriptionPlan plan,
    required SubscriptionBillingCycle billingCycle,
  }) async => _unavailable();

  @override
  Future<SubscriptionPaymentVerification> verifyPayment(
    String reference,
  ) async => _unavailable();

  @override
  Future<SubscriptionCheckoutSession> initializeRegistrationCheckout({
    required String applicationId,
    required String accessToken,
    required SubscriptionBillingCycle billingCycle,
    bool retry = false,
  }) async => _unavailable();

  @override
  Future<SubscriptionPaymentVerification> verifyRegistrationPayment({
    required String applicationId,
    required String accessToken,
    required String reference,
  }) async => _unavailable();

  @override
  Future<ServerClinicSubscription> cancelRenewal(String clinicId) async =>
      _unavailable();

  @override
  Future<ServerClinicSubscription> reactivateSubscription(
    String clinicId,
  ) async => _unavailable();
}

DateTime? _date(dynamic value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

String subscriptionPaymentVerificationMessage(
  SubscriptionPaymentVerification verification,
) {
  if (verification.applicationApproved) {
    return switch (verification.activationDeliveryMethod) {
      'email' =>
        'Payment confirmed. Your clinic was approved and the administrator activation email was sent.',
      'email_failed' =>
        'Payment confirmed and your clinic was approved, but the activation email could not be delivered. Contact AVERA support.',
      'manual' =>
        'Payment confirmed and your clinic was approved. Email delivery is not configured; contact AVERA support for the activation link.',
      _ =>
        'Payment confirmed. Your clinic was approved and administrator activation is pending.',
    };
  }
  if (verification.isTestMode && !verification.subscriptionApplied) {
    return 'Payment verified successfully in test mode. No subscription changes were applied.';
  }
  if (!verification.subscriptionApplied) {
    return 'Payment confirmed. Your clinic application remains pending approval.';
  }
  return 'Payment confirmed securely.';
}
