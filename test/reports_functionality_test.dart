import 'dart:convert';

import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/reports/screens/reports_screen.dart';
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
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ReportsScreen()),
    );

    expect(find.text('Daily Consultations'), findsOneWidget);
    expect(find.text('Inventory Value'), findsOneWidget);
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

      expect(find.text('0 record(s)'), findsOneWidget);
      expect(
        find.text('No clinic records matched the selected filters.'),
        findsOneWidget,
      );
      expect(find.text('Save PDF'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
}

UserSession _session() => UserSession(
  user: AppUser(
    userId: 'reports-user',
    clinicId: 'reports-clinic',
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
    clinicId: 'reports-clinic',
    clinicName: 'Reports Veterinary Clinic',
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
