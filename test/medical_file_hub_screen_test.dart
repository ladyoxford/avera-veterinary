import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/remote/cloud_clinical_state.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/core/theme/theme_controller.dart';
import 'package:avera/features/animals/screens/medical_file_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _patientId = '6a5f8a0b-0b69-41ba-b24f-9ae5ced997b8';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test('remote patient cache preserves estimated-age metadata', () {
    final patient = _medicalFile().patient;
    final restored = RemotePatient.fromJson(patient.toJson());

    expect(restored.dateOfBirth, DateTime(2025, 4, 6));
    expect(restored.isDateOfBirthEstimated, isTrue);
    expect(restored.originalAgeValue, 1);
    expect(restored.originalAgeUnit, 'years');
    expect(restored.ageRecordedAt, DateTime(2026, 4, 6));
  });

  testWidgets('estimated Medical File age advances with the reference date', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(preferences, ageReferenceDate: DateTime(2026, 8, 6)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1 year, 4 months'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _subject(preferences, ageReferenceDate: DateTime(2027, 8, 6)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2 years, 4 months'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'production medical file restores the compact patient summary and Quick Access grid',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_subject(preferences));
      await tester.pumpAndSettle();

      expect(find.text('Medical File'), findsOneWidget);
      expect(find.text('Luna \u2022 AVR-2026-00001'), findsOneWidget);
      expect(find.textContaining('1 year, 4 months'), findsOneWidget);
      expect(find.textContaining('AVR-2026-00001'), findsWidgets);
      expect(find.textContaining('15.0 kg'), findsOneWidget);
      expect(
        find.byKey(const Key('medical-file-patient-facts')),
        findsOneWidget,
      );
      expect(find.text('Hospital number'), findsNothing);
      expect(find.text('Species'), findsNothing);
      expect(
        find.byKey(const Key('medical-file-quick-access-grid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('medical-file-compact-overview')),
        findsNothing,
      );
      expect(find.byKey(const Key('medical-file-tile-overview')), findsNothing);
      expect(
        find.byKey(const Key('medical-file-tile-surgery')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('medical-file-tile-hospitalization')),
        findsOneWidget,
      );
      final quickAccessTiles = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'medical-file-tile-',
            ),
      );
      expect(quickAccessTiles, findsNWidgets(8));

      final firstRow = [
        'signalment',
        'owner',
        'medical_history',
        'consultations',
      ].map((id) => tester.getCenter(find.byKey(Key('medical-file-tile-$id'))));
      final secondRow = [
        'vaccinations',
        'laboratory',
        'surgery',
        'hospitalization',
      ].map((id) => tester.getCenter(find.byKey(Key('medical-file-tile-$id'))));
      expect(firstRow.map((point) => point.dy).toSet().length, 1);
      expect(secondRow.map((point) => point.dy).toSet().length, 1);
      expect(secondRow.first.dy, greaterThan(firstRow.first.dy));
      expect(
        firstRow.map((point) => point.dx).toList(),
        orderedEquals(firstRow.map((point) => point.dx).toList()..sort()),
      );
      final firstRowIconTops =
          ['signalment', 'owner', 'medical_history', 'consultations'].map(
            (id) =>
                tester.getTopLeft(find.byKey(Key('medical-file-icon-$id'))).dy,
          );
      final secondRowIconTops =
          ['vaccinations', 'laboratory', 'surgery', 'hospitalization'].map(
            (id) =>
                tester.getTopLeft(find.byKey(Key('medical-file-icon-$id'))).dy,
          );
      expect(firstRowIconTops.toSet().length, 1);
      expect(secondRowIconTops.toSet().length, 1);
      expect(
        find.descendant(
          of: find.byKey(const Key('medical-file-label-consultations')),
          matching: find.text('Consultations'),
        ),
        findsOneWidget,
      );
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Quick Access remains usable on a small light-theme phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _subject(
        preferences,
        theme: AppTheme.light(),
        textScaler: const TextScaler.linear(1.3),
      ),
    );
    await tester.pumpAndSettle();

    final moreRecords = find.byKey(const Key('medical-file-more-records'));
    await tester.scrollUntilVisible(
      moreRecords,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(moreRecords, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every default record destination retains the production UUID', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 873));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_subject(preferences));
    await tester.pumpAndSettle();

    const recordIds = [
      'signalment',
      'owner',
      'medical_history',
      'consultations',
      'vaccinations',
      'laboratory',
      'surgery',
      'hospitalization',
    ];
    for (final recordId in recordIds) {
      final tile = find.byKey(Key('medical-file-tile-$recordId'));
      await tester.scrollUntilVisible(
        tile,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tile, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Signalment retains detailed demographics and dynamic age', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_subject(preferences));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('medical-file-tile-signalment')));
    await tester.pumpAndSettle();

    expect(find.text('Hospital number'), findsOneWidget);
    expect(find.text('Species'), findsOneWidget);
    expect(find.text('Breed'), findsOneWidget);
    expect(find.text('Sex'), findsOneWidget);
    expect(find.text('Age'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('1 year, 4 months'), findsOneWidget);
    expect(find.text('15.0 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('All Records does not expose the removed Overview destination', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(preferences));
    await tester.pumpAndSettle();
    final moreRecords = find.byKey(const Key('medical-file-more-records'));
    await tester.scrollUntilVisible(
      moreRecords,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(moreRecords);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('medical-file-pin-overview')), findsNothing);
    expect(find.text('Overview'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy Overview preference migrates to the eight current modules',
    (tester) async {
      const preferenceKey =
          'avera_medical_file_quick_access_v1_clinic-1_user-1';
      await preferences.setStringList(preferenceKey, const [
        'overview',
        'signalment',
        'owner',
        'medical_history',
        'consultations',
        'vaccinations',
        'laboratory',
        'hospitalization',
      ]);

      await tester.pumpWidget(_subject(preferences));
      await tester.pumpAndSettle();

      final saved = preferences.getStringList(preferenceKey);
      expect(saved, hasLength(8));
      expect(saved, isNot(contains('overview')));
      expect(saved, contains('surgery'));
      expect(find.byKey(const Key('medical-file-tile-overview')), findsNothing);
      expect(
        find.byKey(const Key('medical-file-tile-surgery')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty production category opens a professional state with contextual action',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_subject(preferences));
      await tester.pumpAndSettle();

      final consultations = find.byKey(
        const Key('medical-file-tile-consultations'),
      );
      await tester.scrollUntilVisible(
        consultations,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(consultations),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(consultations);
      await tester.pumpAndSettle();

      expect(find.text('No consultations yet'), findsOneWidget);
      expect(find.text('New Consultation'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'More Records pinning updates Quick Access and enforces the limit',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_subject(preferences));
      await tester.pumpAndSettle();

      final moreRecords = find.byKey(const Key('medical-file-more-records'));
      await tester.scrollUntilVisible(
        moreRecords,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(moreRecords);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('medical-file-all-records-screen')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('medical-file-pin-signalment')));
      await tester.pump();
      final medicationsPin = find.byKey(
        const Key('medical-file-pin-medications'),
      );
      await tester.scrollUntilVisible(
        medicationsPin,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(medicationsPin);
      await tester.pump();
      expect(find.text('PINNED'), findsWidgets);

      final billingPin = find.byKey(const Key('medical-file-pin-billing'));
      await tester.scrollUntilVisible(
        billingPin,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(billingPin);
      await tester.pump();
      expect(find.text('You can pin up to 8 records.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('medical-file-all-records-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('medical-file-tile-overview')), findsNothing);
      expect(
        find.byKey(const Key('medical-file-tile-signalment')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('medical-file-tile-medications')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pinned records can be reordered and persist their order', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(preferences));
    await tester.pumpAndSettle();
    final allRecords = find.byKey(const Key('medical-file-more-records'));
    await tester.scrollUntilVisible(
      allRecords,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(allRecords);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('medical-file-reorder-owner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('medical-file-all-records-done')));
    await tester.pumpAndSettle();

    final saved = preferences.getStringList(
      'avera_medical_file_quick_access_v1_clinic-1_user-1',
    );
    expect(saved?.take(2), ['owner', 'signalment']);
    expect(tester.takeException(), isNull);
  });
}

Widget _subject(
  SharedPreferences preferences, {
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  DateTime? ageReferenceDate,
}) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(preferences),
    animalAgeReferenceDateProvider.overrideWith(
      (ref) => ageReferenceDate ?? DateTime(2026, 8, 6),
    ),
    userSessionProvider.overrideWith((ref) async => _session()),
    remotePatientMedicalFileProvider.overrideWith((ref, patientId) async {
      expect(patientId, _patientId);
      return _medicalFile();
    }),
    remotePatientSectionProvider.overrideWith(
      (ref, request) async => const RemotePage(
        items: [],
        page: 1,
        pageSize: 25,
        total: 0,
        hasNextPage: false,
      ),
    ),
    clinicalRemoteDataSourceProvider.overrideWithValue(
      _FakeClinicalRemoteDataSource(),
    ),
  ],
  child: MaterialApp(
    theme: theme ?? AppTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: const CloudMedicalFileHubScreen(patientId: _patientId),
  ),
);

RemotePatientMedicalFile _medicalFile() => RemotePatientMedicalFile(
  patient: RemotePatient(
    id: _patientId,
    hospitalNumber: 'AVR-2026-00001',
    name: 'Luna',
    species: 'Cat',
    status: 'Active',
    ownerName: 'Ada Okafor',
    ownerPhone: '08010000000',
    breed: 'Domestic Shorthair',
    sex: 'Female',
    dateOfBirth: DateTime(2025, 4, 6),
    isDateOfBirthEstimated: true,
    originalAgeValue: 1,
    originalAgeUnit: 'years',
    ageRecordedAt: DateTime(2026, 4, 6),
    currentWeightKg: 15.0,
  ),
  summaries: {
    'consultations': {'count': 0},
    'vaccinations': {'count': 0},
    'laboratory': {'count': 0},
    'hospitalizations': {'count': 0},
  },
  timeline: [],
);

UserSession _session() => UserSession(
  user: AppUser(
    userId: 'user-1',
    clinicId: 'clinic-1',
    fullName: 'Clinic Administrator',
    username: 'admin@avera.test',
    email: 'admin@avera.test',
    passwordHash: 'not-used',
    role: 'Clinic Administrator',
    accountType: AccountTypes.clinicAdministrator,
    permissions: '[]',
    invitationStatus: 'Accepted',
    requiresPasswordChange: false,
    twoFactorEnabled: false,
    accountStatus: 'Active',
    membershipStatus: 'Active',
    rememberMe: false,
    sessionTimeoutMinutes: 30,
    createdAt: DateTime(2026, 1, 1),
  ),
  clinic: Clinic(
    clinicId: 'clinic-1',
    clinicName: 'Avera Veterinary Clinic',
    clinicType: 'Veterinary Clinic',
    currency: 'NGN',
    timeZone: 'Africa/Lagos',
    preferredLanguage: 'English',
    themeColor: '#087F7B',
    dateRegistered: DateTime(2026, 1, 1),
    subscriptionPlan: 'Professional',
    clinicStatus: 'Active',
    patientNumberSequenceLength: 5,
    patientNumberResetYearly: true,
    patientNumberPrefixReviewed: true,
  ),
  backendPermissions: const {
    Permissions.patientsView,
    Permissions.consultationsView,
    Permissions.consultationsCreate,
  },
);

class _FakeClinicalRemoteDataSource extends ClinicalRemoteDataSource {
  _FakeClinicalRemoteDataSource()
    : super(
        ApiClient(
          baseUrl: 'https://example.test',
          tokens: const TokenStore(FlutterSecureStorage()),
        ),
      );

  @override
  Future<RemotePage<Map<String, dynamic>>> patientSection(
    String patientId,
    String section, {
    int page = 1,
  }) async {
    expect(patientId, _patientId);
    return RemotePage(
      items: const [],
      page: page,
      pageSize: 25,
      total: 0,
      hasNextPage: false,
    );
  }
}
