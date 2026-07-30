import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/subscription/subscription_plan_config.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/authentication/screens/clinic_registration_screen.dart';
import 'package:avera/features/shared/widgets/subscription_widgets.dart';

void main() {
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
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
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
