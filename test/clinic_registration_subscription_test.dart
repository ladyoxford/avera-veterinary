import 'package:drift/native.dart';
import 'package:avera/core/config/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/subscription/subscription_plan_config.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/authentication/screens/clinic_registration_payment_screen.dart';
import 'package:avera/features/authentication/screens/clinic_registration_screen.dart';
import 'package:avera/features/shared/widgets/subscription_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('subscription catalogue is complete and preserves storage labels', () {
    expect(SubscriptionPlanCatalogue.plans.length, 3);
    expect(SubscriptionPlan.starter.label, 'Starter');
    expect(SubscriptionPlan.professional.label, 'Professional');
    expect(SubscriptionPlan.enterprise.label, 'Enterprise');
    expect(SubscriptionPlanCatalogue.comparisonRows.length, 15);
    expect(
      SubscriptionPlanCatalogue.comparisonRows.map((row) => row.benefit),
      containsAllInOrder([
        'Digital medical records',
        'Appointments and hospitalization',
        'Inventory and billing',
        'Staff roles and permissions',
        'Basic Vera AI',
        'AI clinical documentation',
        'AI differential and treatment assistance',
        'Drug safety and dose intelligence',
        'Workflow automation',
        'Advanced reports and analytics',
        'Multi-clinic command centre',
        'Predictive business intelligence',
        'External integrations and API access',
        'Custom enterprise workflows',
        'Dedicated implementation support',
      ]),
    );
  });

  test(
    'selected subscription label persists through clinic application',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);

      final submitted = await repository.submitClinicApplication(
        const ClinicApplication(
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
          timeZone: 'Africa/Lagos',
        ),
      );

      final clinic = await database.select(database.clinics).getSingle();
      expect(submitted.subscriptionPlan, SubscriptionPlan.enterprise.label);
      expect(clinic.subscriptionPlan, SubscriptionPlan.enterprise.label);
    },
  );

  testWidgets('mobile fields stack and plan cards replace the dropdown', (
    tester,
  ) async {
    await _pumpRegistration(tester, size: const Size(390, 844));
    await _scrollRegistrationUntilVisible(
      tester,
      find.byKey(const Key('clinic-country-field')),
    );
    final cityRect = tester.getRect(find.byKey(const Key('clinic-city-field')));
    final countryRect = tester.getRect(
      find.byKey(const Key('clinic-country-field')),
    );
    expect(countryRect.top, greaterThan(cityRect.bottom));
    expect(countryRect.left, cityRect.left);
    expect(countryRect.width, closeTo(cityRect.width, 1));
    expect(find.text('COUNTRY'), findsOneWidget);

    await _scrollRegistrationUntilVisible(
      tester,
      find.byKey(const Key('clinic-time-zone-field')),
    );
    expect(find.text('TIME ZONE'), findsOneWidget);
    expect(find.text('Africa/Lagos'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    await _scrollRegistrationUntilVisible(
      tester,
      find.byKey(const Key('subscription-plan-professional')),
    );
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.text('Selected Subscription Plan'), findsNothing);
    expect(find.byKey(const Key('plan-benefit-check')), findsWidgets);

    await tester.tap(find.byKey(const Key('subscription-plan-professional')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SubscriptionPlanCard>(
            find.byKey(const Key('subscription-plan-professional')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<SubscriptionPlanCard>(
            find.byKey(const Key('subscription-plan-starter')),
          )
          .selected,
      isFalse,
    );
    await _scrollRegistrationUntilVisible(
      tester,
      find.text('Continue with Professional'),
    );
    expect(find.text('Continue with Professional'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('country selector uses the field ISO value for selection', (
    tester,
  ) async {
    await _pumpRegistration(tester, size: const Size(390, 844));
    final countryField = find.byKey(const Key('clinic-country-field'));
    await _scrollRegistrationUntilVisible(tester, countryField);
    expect(find.text('Nigeria'), findsOneWidget);
    await tester.tap(countryField);
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('country-selection-search'));
    await tester.enterText(search, 'Nigeria');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('country-NG')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('country-NG')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );

    await tester.enterText(search, 'GB');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('country-GB')), findsOneWidget);
    expect(find.text('United Kingdom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison selection preserves registration form state', (
    tester,
  ) async {
    await _pumpRegistration(tester, size: const Size(430, 900));
    final clinicNameInput = find.descendant(
      of: find.byKey(const Key('clinic-name-field')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(clinicNameInput, 'Crest Veterinary Hospital');

    await _scrollRegistrationUntilVisible(
      tester,
      find.byKey(const Key('compare-all-features')),
    );
    await tester.tap(find.byKey(const Key('compare-all-features')));
    await tester.pumpAndSettle();

    expect(find.text('See exactly what each plan unlocks'), findsOneWidget);
    expect(find.text('Dedicated implementation support'), findsOneWidget);
    expect(find.byKey(const Key('comparison-included-icon')), findsWidgets);
    expect(find.byKey(const Key('comparison-unavailable')), findsWidgets);
    expect(
      find.byKey(const Key('subscription-comparison-horizontal-scroll')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('compare-select-enterprise')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('compare-select-enterprise')));
    await tester.pumpAndSettle();

    expect(find.byType(ClinicRegistrationScreen), findsOneWidget);
    await _scrollRegistrationUntilVisible(
      tester,
      find.byKey(const Key('clinic-name-field')),
      upward: true,
    );
    expect(
      tester.widget<TextFormField>(clinicNameInput).controller!.text,
      'Crest Veterinary Hospital',
    );
    await _scrollRegistrationUntilVisible(
      tester,
      find.text('Continue with Enterprise'),
    );
    expect(find.text('Continue with Enterprise'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscription cards render safely in dark theme', (tester) async {
    await _pumpRegistration(
      tester,
      size: const Size(390, 844),
      themeMode: ThemeMode.dark,
    );
    await _scrollRegistrationUntilVisible(
      tester,
      find.byKey(const Key('subscription-plan-enterprise')),
    );
    expect(
      find.text('AI-powered veterinary hospital operating system.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('plan-benefit-check')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'submitted application offers payment without submitting a second application',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _PaymentReadyClinicRepository(database);
      await _pumpRegistration(
        tester,
        size: const Size(390, 844),
        repository: repository,
      );

      await _enterRegistrationField(
        tester,
        const Key('clinic-name-field'),
        'Crest Veterinary Hospital',
      );
      await _enterRegistrationField(
        tester,
        const Key('clinic-email-field'),
        'hello@crest.test',
      );
      await _enterRegistrationField(
        tester,
        const Key('clinic-phone-field'),
        '+2348000000000',
      );
      await _enterRegistrationField(
        tester,
        const Key('clinic-address-field'),
        '1 Veterinary Way',
      );
      await _enterRegistrationField(
        tester,
        const Key('clinic-city-field'),
        'Abuja',
      );
      await _enterRegistrationField(
        tester,
        const Key('administrator-name-field'),
        'Crest Administrator',
      );
      await _enterRegistrationField(
        tester,
        const Key('administrator-email-field'),
        'administrator@crest.test',
      );
      await _enterRegistrationField(
        tester,
        const Key('administrator-phone-field'),
        '+2348111111111',
      );

      final enterprise = find.byKey(const Key('subscription-plan-enterprise'));
      await _scrollRegistrationUntilVisible(tester, enterprise);
      await tester.tap(enterprise);
      await tester.pumpAndSettle();
      final terms = find.byKey(const Key('clinic-registration-terms'));
      await _scrollRegistrationUntilVisible(tester, terms);
      await tester.tap(terms);
      await tester.pumpAndSettle();
      final submit = find.text('Continue with Enterprise');
      await _scrollRegistrationUntilVisible(tester, submit);
      await tester.tap(submit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Application submitted'), findsOneWidget);
      expect(find.text('Continue to Payment'), findsOneWidget);
      expect(find.textContaining('Plan: Enterprise'), findsOneWidget);
      expect(find.textContaining('Payment: Pending'), findsOneWidget);
      expect(repository.submissionCount, 1);
      expect(repository.submitted?.subscriptionPlan, 'Enterprise');

      await tester.tap(
        find.byKey(const Key('continue-to-registration-payment')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClinicRegistrationPaymentScreen), findsOneWidget);
      expect(find.text('AVR-20260818-ABC123'), findsOneWidget);
      expect(find.text('Enterprise'), findsOneWidget);
      expect(find.text('Pending approval'), findsOneWidget);
      expect(repository.submissionCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('registration explains throttling and preserves entered form data', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _pumpRegistration(
      tester,
      size: const Size(390, 844),
      repository: _FailingClinicRepository(
        database,
        const ApiException(
          'rate_limit_exceeded',
          'Too many requests were made. Please wait a few minutes and try again.',
          statusCode: 429,
        ),
      ),
    );
    await _completeRequiredRegistrationFields(tester);

    final submit = find.text('Continue with Starter');
    await _scrollRegistrationUntilVisible(tester, submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Too many requests were made. Please wait a few minutes and try again. Your form has been preserved.',
      ),
      findsOneWidget,
    );
    await _scrollRegistrationUntilVisible(
      tester,
      find.byKey(const Key('clinic-name-field')),
      upward: true,
    );
    final clinicName = tester.widget<TextFormField>(
      find.descendant(
        of: find.byKey(const Key('clinic-name-field')),
        matching: find.byType(TextFormField),
      ),
    );
    expect(clinicName.controller!.text, 'Crest Veterinary Hospital');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _completeRequiredRegistrationFields(WidgetTester tester) async {
  const fields = <(Key, String)>[
    (Key('clinic-name-field'), 'Crest Veterinary Hospital'),
    (Key('clinic-email-field'), 'hello@crest.test'),
    (Key('clinic-phone-field'), '+2348000000000'),
    (Key('clinic-address-field'), '1 Veterinary Way'),
    (Key('clinic-city-field'), 'Abuja'),
    (Key('administrator-name-field'), 'Crest Administrator'),
    (Key('administrator-email-field'), 'administrator@crest.test'),
    (Key('administrator-phone-field'), '+2348111111111'),
  ];
  for (final (key, value) in fields) {
    await _enterRegistrationField(tester, key, value);
  }
  final terms = find.byKey(const Key('clinic-registration-terms'));
  await _scrollRegistrationUntilVisible(tester, terms);
  await tester.tap(terms);
  await tester.pumpAndSettle();
}

Future<void> _enterRegistrationField(
  WidgetTester tester,
  Key key,
  String value,
) async {
  final container = find.byKey(key);
  await _scrollRegistrationUntilVisible(tester, container);
  final input = find.descendant(
    of: container,
    matching: find.byType(TextFormField),
  );
  await tester.enterText(input, value);
  await tester.pump();
}

Future<void> _scrollRegistrationUntilVisible(
  WidgetTester tester,
  Finder target, {
  bool upward = false,
}) async {
  final form = find.byKey(const Key('clinic-registration-form'));
  for (var attempt = 0; attempt < 20; attempt++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(form, Offset(0, upward ? 600 : -600));
    await tester.pumpAndSettle();
  }
  fail('Could not reveal the target widget in the registration form.');
}

Future<void> _pumpRegistration(
  WidgetTester tester, {
  required Size size,
  ThemeMode themeMode = ThemeMode.light,
  ClinicRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          clinicRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: const ClinicRegistrationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _PaymentReadyClinicRepository extends ClinicRepository {
  _PaymentReadyClinicRepository(super.database);

  int submissionCount = 0;
  ClinicApplication? submitted;

  @override
  Future<ClinicApplication> submitClinicApplication(
    ClinicApplication application,
  ) async {
    submissionCount += 1;
    submitted = application;
    return ClinicApplication(
      clinicName: application.clinicName,
      clinicEmail: application.clinicEmail,
      phoneNumber: application.phoneNumber,
      address: application.address,
      city: application.city,
      country: application.country,
      administratorName: application.administratorName,
      administratorEmail: application.administratorEmail,
      administratorPhone: application.administratorPhone,
      professionalTitle: application.professionalTitle,
      subscriptionPlan: application.subscriptionPlan,
      timeZone: application.timeZone,
      reference: 'AVR-20260818-ABC123',
      applicationId: 'application-1',
      clinicId: 'clinic-1',
      paymentStatus: 'Pending',
      paymentAccessToken: 'scoped-registration-capability',
    );
  }
}

class _FailingClinicRepository extends ClinicRepository {
  _FailingClinicRepository(super.database, this.error);

  final Object error;

  @override
  Future<ClinicApplication> submitClinicApplication(
    ClinicApplication application,
  ) async {
    throw error;
  }
}
