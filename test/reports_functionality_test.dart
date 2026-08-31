import 'dart:convert';

import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/reports/screens/reports_screen.dart';
import 'package:avera/features/reports/screens/inventory_transfer_screens.dart';
import 'package:avera/features/reports/services/canonical_inventory_records.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Reports exposes all three reports and both transfer flows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ReportsScreen()),
    );

    expect(find.text('Daily Consultations'), findsOneWidget);
    expect(find.text('Inventory Stock & Valuation'), findsOneWidget);
    expect(find.text('Vaccination Report'), findsOneWidget);
    expect(find.text('DATA IMPORT & EXPORT'), findsOneWidget);
    expect(find.text('Import Inventory'), findsOneWidget);
    expect(find.text('Export Records'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final type in ClinicReportType.values) {
    testWidgets('${type.name} report loads its live local tenant query', (
      tester,
    ) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            userSessionProvider.overrideWith((ref) async => _session()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ReportDetailScreen(type: type),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0'), findsAtLeastNWidgets(1));
      expect(
        find.text(switch (type) {
          ClinicReportType.dailyConsultations => 'No consultations found',
          ClinicReportType.inventoryValue => 'No inventory products',
          ClinicReportType.vaccination => 'No vaccinations found',
        }),
        findsOneWidget,
      );
      expect(find.text('Save PDF'), findsOneWidget);
      if (type != ClinicReportType.inventoryValue) {
        expect(
          find.byKey(Key('${type.routeKey}-quick-period-row')),
          findsOneWidget,
        );
        expect(find.text('Today'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('vaccination status survives shared timeframe Apply', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          userSessionProvider.overrideWith((ref) async => _session()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ReportDetailScreen(type: ClinicReportType.vaccination),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Due'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vaccination-period-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vaccination-period-1w')), findsNothing);
    await tester.tap(find.byKey(const Key('vaccination-period-7d')));
    await tester.tap(find.byKey(const Key('apply-vaccination-period')));
    await tester.pumpAndSettle();

    final control = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(control.selected, {'Due'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'seven canonical products appear in valuation and export with tenant isolation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedInventoryFixture(database);
      final repository = ClinicRepository(database);
      final clinicA = await repository.readPermittedInventory(_session());

      expect(clinicA, hasLength(7));
      expect(clinicA.map((item) => item.drugName), contains('Manual Product'));
      expect(
        clinicA.map((item) => item.drugName),
        contains('Imported Product'),
      );
      expect(clinicA.any((item) => item.drugName == 'Archived Product'), false);
      expect(clinicA.any((item) => item.drugName == 'Clinic B Product'), false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            userSessionProvider.overrideWith((ref) async => _session()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ReportDetailScreen(
              type: ClinicReportType.inventoryValue,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inventory Stock & Valuation'), findsOneWidget);
      expect(find.text('Manual Product'), findsOneWidget);
      expect(find.text('Imported Product'), findsOneWidget);
      expect(find.text('No inventory products'), findsNothing);
      expect(find.text('7'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            userSessionProvider.overrideWith((ref) async => _session()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ExportRecordsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('7 products'), findsOneWidget);
      expect(find.textContaining('Export 7 Products'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('remote inventory mapping preserves missing and known zero cost', () {
    final missing = inventoryExportRecordFromRemote(
      _remoteItem(id: 'missing', purchasePrice: null),
    );
    final zero = inventoryExportRecordFromRemote(
      _remoteItem(id: 'zero', purchasePrice: 0),
    );

    expect(missing.costPrice, isNull);
    expect(zero.costPrice, 0);
  });

  test('production report lists use UTC boundaries and paginate', () async {
    FlutterSecureStorage.setMockInitialValues({
      'avera_access_token': 'access-token',
    });
    final requests = <Uri>[];
    final source = ClinicalRemoteDataSource(
      ApiClient(
        baseUrl: 'https://api.avera.test',
        tokens: const TokenStore(FlutterSecureStorage()),
        client: MockClient((request) async {
          requests.add(request.url);
          final page = int.parse(request.url.queryParameters['page']!);
          return http.Response(
            jsonEncode({
              'items': [
                {'consultation_id': 'item-$page'},
              ],
              'page': page,
              'pageSize': 100,
              'total': 101,
              'hasNextPage': page == 1,
            }),
            200,
          );
        }),
      ),
    );
    final from = DateTime(2026, 8, 31);
    final to = DateTime(2026, 8, 31, 23, 59, 59);

    final rows = await source.reportConsultations(from: from, to: to);

    expect(rows, hasLength(2));
    expect(requests, hasLength(2));
    expect(requests.first.path, '/api/v1/consultations');
    expect(requests.first.queryParameters['pageSize'], '100');
    expect(
      requests.first.queryParameters['from'],
      from.toUtc().toIso8601String(),
    );
    expect(requests.first.queryParameters['to'], to.toUtc().toIso8601String());
  });

  test(
    'all-time production reports omit a fabricated lower boundary',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'avera_access_token': 'access-token',
      });
      late Uri requestUri;
      final source = ClinicalRemoteDataSource(
        ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: const TokenStore(FlutterSecureStorage()),
          client: MockClient((request) async {
            requestUri = request.url;
            return http.Response(
              jsonEncode({
                'items': const [],
                'page': 1,
                'pageSize': 100,
                'total': 0,
                'hasNextPage': false,
              }),
              200,
            );
          }),
        ),
      );

      await source.reportVaccinations(from: null, to: DateTime(2026, 8, 31));

      expect(requestUri.queryParameters.containsKey('from'), false);
      expect(
        requestUri.queryParameters['to'],
        DateTime(2026, 8, 31).toUtc().toIso8601String(),
      );
    },
  );
}

Future<void> _seedInventoryFixture(AppDatabase database) async {
  for (final clinic in const [
    (defaultClinicId, 'Reports Veterinary Clinic'),
    ('clinic-b', 'Other Veterinary Clinic'),
  ]) {
    await database
        .into(database.clinics)
        .insert(
          ClinicsCompanion.insert(
            clinicId: clinic.$1,
            clinicName: clinic.$2,
            dateRegistered: DateTime(2026),
          ),
        );
  }
  final names = <String>[
    'Manual Product',
    'Imported Product',
    'Zero Cost Product',
    'Vaccine Fridge',
    'Suture Pack',
    'Infusion Pump',
    'Diagnostic Strips',
  ];
  for (var index = 0; index < names.length; index++) {
    await database
        .into(database.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            clinicId: const Value(defaultClinicId),
            drugName: names[index],
            category: 'Medicines / Drugs',
            categoryId: const Value('drugs'),
            sku: Value(index == 1 ? 'IMPORTED-001' : 'MANUAL-$index'),
            quantity: Value(index + 1),
            buyingPrice: Value(index == 2 ? 0.0 : (index + 1) * 1000.0),
            sellingPrice: Value((index + 1) * 1500.0),
            baseUnitLabel: const Value('unit'),
          ),
        );
  }
  await database
      .into(database.inventoryItems)
      .insert(
        InventoryItemsCompanion.insert(
          clinicId: const Value(defaultClinicId),
          drugName: 'Archived Product',
          category: 'Medicines / Drugs',
          categoryId: const Value('drugs'),
          isArchived: const Value(true),
        ),
      );
  await database
      .into(database.inventoryItems)
      .insert(
        InventoryItemsCompanion.insert(
          clinicId: const Value('clinic-b'),
          drugName: 'Clinic B Product',
          category: 'Medicines / Drugs',
          categoryId: const Value('drugs'),
        ),
      );
}

RemoteInventoryItem _remoteItem({
  required String id,
  required num? purchasePrice,
}) => RemoteInventoryItem(
  id: id,
  name: 'Product $id',
  categoryId: 'drugs',
  categoryName: 'Medicines / Drugs',
  quantity: 1,
  reorderLevel: 0,
  purchasePrice: purchasePrice,
  sellingPrice: 100,
  status: 'Active',
);

UserSession _session({String clinicId = defaultClinicId}) => UserSession(
  user: AppUser(
    userId: 'reports-user',
    clinicId: clinicId,
    fullName: 'Report Administrator',
    username: 'reports@avera.test',
    email: 'reports@avera.test',
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
    createdAt: DateTime(2026),
  ),
  clinic: Clinic(
    clinicId: clinicId,
    clinicName: clinicId == defaultClinicId
        ? 'Reports Veterinary Clinic'
        : 'Other Veterinary Clinic',
    clinicType: 'Veterinary Clinic',
    currency: 'NGN',
    timeZone: 'Africa/Lagos',
    preferredLanguage: 'English',
    themeColor: '#087F7B',
    dateRegistered: DateTime(2026),
    subscriptionPlan: 'Professional',
    clinicStatus: 'Active',
    patientNumberSequenceLength: 5,
    patientNumberResetYearly: true,
    patientNumberPrefixReviewed: true,
  ),
  backendPermissions: const {
    Permissions.reportsExport,
    Permissions.inventoryView,
    Permissions.consultationsView,
    Permissions.vaccinationsView,
  },
);
