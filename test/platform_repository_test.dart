import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/repositories/platform_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('platform overview uses live platform-scoped database values', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final clinics = ClinicRepository(database);
    await clinics.seedSampleData();
    final owner = await clinics.authenticateUser(
      username: 'owner@avera.test',
      password: 'change-me-locally',
    );
    expect(owner, isNotNull);

    final initial = await LocalPlatformRepository(
      database,
    ).loadOverview(owner!);
    expect(initial.totalClinics, 1);
    expect(initial.activeClinics, 1);
    expect(initial.activeUsers, greaterThan(0));
    expect(initial.monthlyRevenue, isNull);
    expect(initial.systemHealthStatus, isNull);

    await (database.update(database.clinics)
          ..where((clinic) => clinic.clinicId.equals(defaultClinicId)))
        .write(const ClinicsCompanion(clinicStatus: Value('Suspended')));

    final updated = await LocalPlatformRepository(database).loadOverview(owner);
    expect(updated.activeClinics, 0);
    expect(updated.suspendedClinics, 1);
    expect(updated.recentClinics.single.clinicId, defaultClinicId);
  });

  test('clinic users cannot open a platform overview stream', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final clinics = ClinicRepository(database);
    await clinics.seedSampleData();
    final administrator = await clinics.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    expect(administrator, isNotNull);

    expect(
      () => LocalPlatformRepository(database).watchOverview(administrator!),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'remote platform overview fetches PostgreSQL data and caches pending clinics',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      final requestedPaths = <String>[];
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            requestedPaths.add(request.url.path);
            return http.Response(
              jsonEncode({
                'totalClinics': 1,
                'activeClinics': 0,
                'pendingApplications': 1,
                'suspendedClinics': 0,
                'activeUsers': 1,
                'expiredSubscriptions': 0,
                'monthlyRevenueMinor': 0,
                'currency': 'NGN',
                'recentClinics': [_remoteClinic(status: 'PendingApproval')],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final overview = await repository.loadOverview(session);

      expect(requestedPaths, ['/api/v1/platform/overview']);
      expect(overview.pendingApplications, 1);
      expect(overview.recentClinics.single.clinicStatus, 'Pending');
      final cached = await (database.select(
        database.clinics,
      )..where((row) => row.clinicId.equals('remote-clinic'))).getSingle();
      expect(cached.clinicName, 'Remote Veterinary Clinic');
      expect(cached.clinicStatus, 'Pending');
    },
  );

  test(
    'cached platform clinics remain visible when the backend fails',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      await database
          .into(database.clinics)
          .insertOnConflictUpdate(
            ClinicsCompanion.insert(
              clinicId: 'cached-clinic',
              clinicName: 'Cached Veterinary Clinic',
              clinicStatus: const Value('Pending'),
              dateRegistered: DateTime(2026),
            ),
          );
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      var offline = false;
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'error': 'temporarily_unavailable'}),
              503,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
        onOfflineChanged: (value) => offline = value,
      );

      final clinics = await repository.loadClinics(session, status: 'Pending');

      expect(
        clinics.map((clinic) => clinic.clinicId),
        contains('cached-clinic'),
      );
      expect(offline, true);
    },
  );

  test(
    'remote platform clinic list includes and caches registrations awaiting payment',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      late Uri requestedUri;
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(
              jsonEncode({
                'items': [_remoteClinic(status: 'RegistrationDraft')],
                'total': 1,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final clinics = await repository.loadClinics(session);

      expect(requestedUri.path, '/api/v1/platform/clinics');
      expect(requestedUri.queryParameters['pageSize'], '100');
      expect(clinics.single.clinicStatus, 'Awaiting Payment');
      final pending = await LocalPlatformRepository(
        database,
      ).loadClinics(session, status: 'Pending');
      expect(
        pending.map((clinic) => clinic.clinicId),
        contains('remote-clinic'),
      );
    },
  );

  test(
    'platform clinic detail preserves application reference and payment status',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/platform/clinics/remote-clinic');
            return http.Response(
              jsonEncode({
                'clinic': {
                  ..._remoteClinic(status: 'PendingApproval'),
                  'applicationReference': 'AVR-20260818-ABC123',
                  'paymentStatus': 'TestVerified',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final payment = await repository.loadClinicApplicationPayment(
        session,
        'remote-clinic',
      );

      expect(payment, isNotNull);
      expect(payment!.applicationReference, 'AVR-20260818-ABC123');
      expect(payment.paymentStatus, 'TestVerified');
    },
  );

  test(
    'approving a clinic calls the backend and refreshes the Drift cache',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      late http.Request captured;
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({'clinic': _remoteClinic(status: 'Active')}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final clinic = await repository.updateClinicStatus(
        session: session,
        clinicId: 'remote-clinic',
        status: 'Active',
      );

      expect(captured.method, 'PATCH');
      expect(
        captured.url.path,
        '/api/v1/platform/clinics/remote-clinic/status',
      );
      expect(jsonDecode(captured.body), {'status': 'Active'});
      expect(clinic.clinicStatus, 'Active');
      final cached = await (database.select(
        database.clinics,
      )..where((row) => row.clinicId.equals('remote-clinic'))).getSingle();
      expect(cached.clinicStatus, 'Active');
    },
  );

  test(
    'approval and resend parse the provider-submitted activation contract without exposing a token',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      final requests = <http.Request>[];
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            requests.add(request);
            final activation = {
              'status': 'PendingActivation',
              'email': 'ada@example.com',
              'deliveryMethod': 'email_submitted',
              'emailState': 'Submitted',
              'provider': 'resend',
              'providerMessageId': 'resend-message-1',
              'submittedAt': '2026-08-30T08:05:00.000Z',
              'canResend': true,
            };
            return http.Response(
              jsonEncode(
                request.method == 'PATCH'
                    ? {
                        'clinic': _remoteClinic(status: 'Active'),
                        'activation': activation,
                      }
                    : {'activation': activation},
              ),
              200,
            );
          }),
        ),
      );

      final approved = await repository.approveClinic(
        session: session,
        clinicId: 'remote-clinic',
      );
      final resent = await repository.resendAdministratorActivation(
        session: session,
        clinicId: 'remote-clinic',
      );

      expect(approved.activation.deliveryMethod, 'email_submitted');
      expect(approved.activation.emailState, 'Submitted');
      expect(approved.activation.provider, 'resend');
      expect(approved.activation.providerMessageId, 'resend-message-1');
      expect(approved.activation.submittedAt, isNotNull);
      expect(approved.activation.activationUrl, isNull);
      expect(resent.canResend, true);
      expect(requests.first.method, 'PATCH');
      expect(requests.last.method, 'POST');
      expect(
        requests.last.url.path,
        '/api/v1/platform/clinics/remote-clinic/administrator-activation/resend',
      );
    },
  );

  test(
    'subscription request sends server filters and preserves server pagination',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      late Uri requestedUri;
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            requestedUri = request.url;
            return http.Response(
              jsonEncode({
                'page': 3,
                'pageSize': 25,
                'total': 126,
                'hasNextPage': true,
                'summary': {
                  'active': 0,
                  'expiring': 0,
                  'expired': 126,
                  'paymentIssues': 0,
                  'monthlyRevenueMinor': 500000,
                },
                'items': [
                  {
                    'clinicId': 'clinic-51',
                    'clinicName': 'Expired Clinic',
                    'plan': 'Professional',
                    'status': 'Expired',
                    'billingCycle': 'monthly',
                  },
                ],
                'payments': [
                  {
                    'reference': 'PAY-LIVE-1',
                    'clinicName': 'Expired Clinic',
                    'amountMinor': 500000,
                    'currency': 'NGN',
                    'status': 'Successful',
                    'mode': 'live',
                  },
                  {
                    'reference': 'PAY-TEST-1',
                    'clinicName': 'Test Clinic',
                    'amountMinor': 10000000,
                    'currency': 'NGN',
                    'status': 'Successful',
                    'mode': 'test',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final result = await repository.loadSubscriptions(
        session,
        status: 'Expired',
        search: 'clinic',
        page: 3,
        pageSize: 25,
      );

      expect(requestedUri.queryParameters, {
        'page': '3',
        'pageSize': '25',
        'status': 'Expired',
        'search': 'clinic',
      });
      expect(result.total, 126);
      expect(result.page, 3);
      expect(result.hasNextPage, true);
      expect(result.monthlyRevenueMinor, 500000);
      expect(result.payments.map((payment) => payment.mode), ['live', 'test']);
    },
  );

  test(
    'mutual deletion uses the request and confirmation backend routes',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final session = await _platformOwnerSession(database);
      final tokens = const TokenStore(FlutterSecureStorage());
      await tokens.save(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      final requests = <http.Request>[];
      final repository = RemotePlatformRepository(
        db: database,
        apiClient: ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: tokens,
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/confirm')) {
              return http.Response(
                jsonEncode({
                  'deletion': {'status': 'Deleted'},
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'deletionRequest': {
                  'requestId': 'request-1',
                  'recipientEmail': 'cl****@example.com',
                  'expiresAt': '2026-08-30T08:20:00.000Z',
                  'attemptsRemaining': 5,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final challenge = await repository.requestClinicDeletion(
        session: session,
        clinicId: 'remote-clinic',
        reason: 'Mutually agreed reset.',
      );
      await repository.confirmClinicDeletion(
        session: session,
        clinicId: 'remote-clinic',
        requestId: challenge.requestId,
        code: '123456',
      );

      expect(challenge.recipientEmail, 'cl****@example.com');
      expect(
        requests.first.url.path,
        '/api/v1/platform/clinics/remote-clinic/deletion-requests',
      );
      expect(requests.first.method, 'POST');
      expect(jsonDecode(requests.first.body), {
        'reason': 'Mutually agreed reset.',
      });
      expect(
        requests.last.url.path,
        '/api/v1/platform/clinics/remote-clinic/deletion-requests/request-1/confirm',
      );
      expect(jsonDecode(requests.last.body), {'code': '123456'});
    },
  );
}

Future<UserSession> _platformOwnerSession(AppDatabase database) async {
  final clinics = ClinicRepository(database);
  await clinics.seedSampleData();
  return (await clinics.authenticateUser(
    username: 'owner@avera.test',
    password: 'change-me-locally',
  ))!;
}

Map<String, dynamic> _remoteClinic({required String status}) => {
  'clinicId': 'remote-clinic',
  'clinicName': 'Remote Veterinary Clinic',
  'email': 'clinic@example.test',
  'phoneNumber': '+2348000000000',
  'address': '1 Clinic Road',
  'city': 'Lagos',
  'country': 'Nigeria',
  'timeZone': 'Africa/Lagos',
  'status': status,
  'subscriptionPlan': 'Professional',
  'registrationDate': '2026-07-31T10:00:00.000Z',
};
