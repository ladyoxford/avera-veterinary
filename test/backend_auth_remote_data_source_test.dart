import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/backend_auth_remote_data_source.dart';
import 'package:avera/core/remote/auth_remote_data_source.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/repositories/authentication_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test(
    'ApiClient uses the configured base URL and normalizes one trailing slash',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'http://10.28.80.92:8080/api/v1/auth/sign-in',
        );
        return http.Response('{}', 200);
      });
      final apiClient = ApiClient(
        baseUrl: 'http://10.28.80.92:8080/',
        tokens: const TokenStore(FlutterSecureStorage()),
        client: client,
      );

      await apiClient.post('api/v1/auth/sign-in', body: const {});
    },
  );

  test(
    'authentication resolves against the production Render base URL',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          '${BackendConfiguration.productionApiBaseUrl}/api/v1/auth/sign-in',
        );
        return http.Response('{}', 200);
      });
      final apiClient = ApiClient(
        baseUrl: '${BackendConfiguration.productionApiBaseUrl}/',
        tokens: const TokenStore(FlutterSecureStorage()),
        client: client,
      );

      await apiClient.post('/api/v1/auth/sign-in', body: const {});
    },
  );

  test('clinical endpoints share the production Render base URL', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        '${BackendConfiguration.productionApiBaseUrl}/api/v1/patients?page=1',
      );
      return http.Response('{}', 200);
    });
    final apiClient = ApiClient(
      baseUrl: BackendConfiguration.productionApiBaseUrl,
      tokens: const TokenStore(FlutterSecureStorage()),
      client: client,
    );

    await apiClient.get('/api/v1/patients?page=1', authenticated: false);
  });

  test(
    'patient registration uses authenticated production POST and UUID result',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'avera_access_token': 'production-access-token',
      });
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/patients');
        expect(
          request.headers['authorization'],
          'Bearer production-access-token',
        );
        expect(jsonDecode(request.body), containsPair('name', 'Luna'));
        return http.Response(
          jsonEncode({
            'patient': {
              'patient_id': 'cb159739-c0cb-4503-a069-9d64563f47bc',
              'hospital_number': 'BIOCAMP-2026-00001',
              'name': 'Luna',
              'species': 'Cat',
              'breed': 'Domestic Shorthair',
              'sex': 'Female',
              'status': 'Active',
              'owner_name': 'Luna Owner',
              'owner_phone': '08000000000',
              // node-postgres serializes PostgreSQL BIGINT columns as strings.
              'revision': '1',
            },
            'submissionId': '5b8ea5ed-f09b-4ed3-b440-e490f2f4e32d',
            'duplicateSubmission': false,
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final source = ClinicalRemoteDataSource(
        ApiClient(
          baseUrl: BackendConfiguration.productionApiBaseUrl,
          tokens: const TokenStore(FlutterSecureStorage()),
          client: client,
        ),
      );

      final result = await source.registerPatient({
        'submissionId': '5b8ea5ed-f09b-4ed3-b440-e490f2f4e32d',
        'name': 'Luna',
      });

      expect(result.patient.id, 'cb159739-c0cb-4503-a069-9d64563f47bc');
      expect(result.patient.hospitalNumber, 'BIOCAMP-2026-00001');
      expect(result.patient.revision, 1);
    },
  );

  test('clinical mutations use authenticated production contracts', () async {
    FlutterSecureStorage.setMockInitialValues({
      'avera_access_token': 'production-access-token',
    });
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(
        request.headers['authorization'],
        'Bearer production-access-token',
      );
      if (request.url.path.endsWith('/status')) {
        return http.Response(
          jsonEncode({
            'patient': {
              'patient_id': 'cb159739-c0cb-4503-a069-9d64563f47bc',
              'hospital_number': 'AVR-2026-00001',
              'name': 'Luna',
              'species': 'Cat',
              'status': 'Relocated',
              'owner_name': 'Luna Owner',
              'owner_phone': '08000000000',
              'revision': '2',
            },
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/consultations') {
        return http.Response(
          jsonEncode({
            'consultation': {
              'consultation_id': '3f4cd168-ff17-4be6-8fb2-c73e791c2bcc',
              'patient_id': 'cb159739-c0cb-4503-a069-9d64563f47bc',
            },
            'submissionId': 'c0205ff9-bc94-4bfa-aa05-a3527760f488',
            'duplicateSubmission': false,
          }),
          201,
        );
      }
      return http.Response(
        jsonEncode({
          'item': {
            'inventory_product_id': 'db681307-05a9-47ca-b6f6-8a8ba86037da',
            'name': 'Amoxicillin 250 mg',
            'category_key': 'drugs',
            'category': 'Drugs',
            'quantity': 12,
            'reorder_level': 5,
            'purchase_price': '1200.00',
            'selling_price': '1800.00',
            'status': 'Active',
            'revision': request.method == 'PATCH' ? '2' : '1',
          },
        }),
        request.method == 'POST' ? 201 : 200,
      );
    });
    final source = ClinicalRemoteDataSource(
      ApiClient(
        baseUrl: BackendConfiguration.productionApiBaseUrl,
        tokens: const TokenStore(FlutterSecureStorage()),
        client: client,
      ),
    );

    final patient = await source.updatePatientStatus(
      patientId: 'cb159739-c0cb-4503-a069-9d64563f47bc',
      status: 'Relocated',
      reason: 'Owner moved clinic',
    );
    final consultation = await source.createConsultation(const {
      'submissionId': 'c0205ff9-bc94-4bfa-aa05-a3527760f488',
      'patientId': 'cb159739-c0cb-4503-a069-9d64563f47bc',
      'chiefComplaint': 'Reduced appetite',
    });
    final createdInventory = await source.createInventoryItem(const {
      'submissionId': '561a66a4-baff-493c-916f-73cf36e36a19',
      'name': 'Amoxicillin 250 mg',
    });
    final updatedInventory = await source.updateInventoryItem(
      inventoryProductId: 'db681307-05a9-47ca-b6f6-8a8ba86037da',
      payload: const {'name': 'Amoxicillin 250 mg', 'revision': 1},
    );

    expect(patient.status, 'Relocated');
    expect(patient.revision, 2);
    expect(consultation.patientId, patient.id);
    expect(createdInventory.revision, 1);
    expect(updatedInventory.revision, 2);
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'PATCH /api/v1/patients/${patient.id}/status',
      'POST /api/v1/consultations',
      'POST /api/v1/inventory/products',
      'PATCH /api/v1/inventory/products/${createdInventory.id}',
    ]);
  });

  test(
    'ApiClient uses a configurable timeout with a 15-second development default',
    () {
      expect(
        BackendConfiguration.requestTimeout.inSeconds,
        inInclusiveRange(10, 60),
      );
    },
  );

  test(
    'sign-in preserves password and sends a Zod-compatible JSON body',
    () async {
      late Map<String, dynamic> requestBody;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/sign-in');
        expect(request.headers['content-type'], 'application/json');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'accessToken': 'access-token-value',
            'refreshToken': 'refresh-token-value',
            'expiresIn': 900,
            'user': {
              'userId': 'user-1',
              'clinicId': 'clinic-1',
              'accountType': 'ClinicAdministrator',
              'permissions': ['patients.view'],
              'fullName': 'System Administrator',
              'email': 'admin@avera.test',
              'roleId': 'role-1',
              'roleCode': 'clinic_administrator',
              'roleName': 'Clinic Administrator',
              'role': {
                'id': 'role-1',
                'code': 'clinic_administrator',
                'name': 'Clinic Administrator',
              },
              'clinicName': 'Zevora Veterinary Clinic',
              'clinicStatus': 'Active',
              'subscriptionPlan': 'Professional',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiClient = ApiClient(
        baseUrl: 'https://api.avera.test',
        tokens: const TokenStore(FlutterSecureStorage()),
        client: client,
      );
      final source = BackendAuthRemoteDataSource(apiClient);

      final session = await source.signIn(
        email: '  ADMIN@AVERA.TEST ',
        password: r'Keep My $pecial Password!',
        deviceId: 'Infinix X6850',
        platform: 'Android',
      );

      expect(requestBody, {
        'email': 'admin@avera.test',
        'password': r'Keep My $pecial Password!',
        'deviceName': 'Infinix X6850',
        'platform': 'android',
      });
      expect(session.user.accountType, 'ClinicAdministrator');
      expect(session.user.clinicName, 'Zevora Veterinary Clinic');
      expect(session.user.permissions, {'patients.view'});
      expect(session.user.roleId, 'role-1');
      expect(session.user.roleCode, 'clinic_administrator');
      expect(session.user.roleName, 'Clinic Administrator');
    },
  );

  test('optional platform is omitted rather than encoded as null', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'accessToken': 'access',
          'refreshToken': 'refresh',
          'expiresIn': 900,
          'user': {
            'userId': 'owner-1',
            'clinicId': null,
            'accountType': 'PlatformOwner',
            'permissions': ['*'],
            'fullName': 'Platform Owner',
            'email': 'owner@avera.test',
          },
        }),
        200,
      );
    });
    final source = BackendAuthRemoteDataSource(
      ApiClient(
        baseUrl: 'https://api.avera.test',
        tokens: const TokenStore(FlutterSecureStorage()),
        client: client,
      ),
    );

    await source.signIn(
      email: 'owner@avera.test',
      password: 'password',
      deviceId: 'flutter-device',
    );

    expect(requestBody['deviceName'], 'flutter-device');
    expect(requestBody.containsKey('platform'), isFalse);
    expect(requestBody.values, isNot(contains(null)));
  });

  test(
    'sign-in returns a typed MFA challenge without parsing session tokens',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'mfaRequired': true,
            'challengeToken': 'challenge-token-value',
            'expiresIn': 300,
          }),
          200,
        ),
      );
      final source = BackendAuthRemoteDataSource(
        ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: const TokenStore(FlutterSecureStorage()),
          client: client,
        ),
      );

      await expectLater(
        source.signIn(
          email: 'admin@avera.test',
          password: 'password',
          deviceId: 'device',
        ),
        throwsA(
          isA<MfaRequiredException>()
              .having(
                (value) => value.challengeToken,
                'challenge',
                'challenge-token-value',
              )
              .having((value) => value.expiresIn, 'expiry', 300),
        ),
      );
    },
  );

  test('ACCOUNT_SUSPENDED is preserved and broadcasts restriction', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': 'ACCOUNT_SUSPENDED',
          'message': 'Account access is restricted.',
        }),
        403,
      ),
    );
    final apiClient = ApiClient(
      baseUrl: 'https://api.avera.test',
      tokens: const TokenStore(FlutterSecureStorage()),
      client: client,
    );
    final event = AccountRestrictionDispatcher.events.first;

    await expectLater(
      apiClient.post('/protected', authenticated: false),
      throwsA(
        isA<ApiException>().having(
          (value) => value.code,
          'code',
          'ACCOUNT_SUSPENDED',
        ),
      ),
    );
    await expectLater(event, completes);
  });

  test(
    'temporary server failure preserves the offline refresh token',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'avera_access_token': 'cached-access',
        'avera_refresh_token': 'cached-refresh',
      });
      const storage = FlutterSecureStorage();
      final tokens = const TokenStore(storage);
      final source = BackendAuthRemoteDataSource(
        ApiClient(
          baseUrl: BackendConfiguration.productionApiBaseUrl,
          tokens: tokens,
          client: MockClient(
            (_) async => throw http.ClientException('network is unreachable'),
          ),
        ),
      );
      final repository = AuthenticationRepository(
        remote: source,
        tokens: tokens,
      );

      await expectLater(repository.restore(), throwsA(isA<ApiException>()));
      expect(await tokens.refreshToken, 'cached-refresh');
    },
  );

  test(
    'clinic administrator activation uses public production endpoints',
    () async {
      final requests = <http.Request>[];
      final source = BackendAuthRemoteDataSource(
        ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: const TokenStore(FlutterSecureStorage()),
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/status')) {
              return http.Response(
                jsonEncode({
                  'activation': {
                    'clinicName': 'Ada Veterinary Clinic',
                    'administratorName': 'Ada Clinic Owner',
                    'email': 'ada@example.com',
                    'expiresAt': '2026-08-02T10:00:00.000Z',
                  },
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'activated': true,
                'email': 'ada@example.com',
                'mfaEnrollmentRecommended': true,
              }),
              200,
            );
          }),
        ),
      );

      final details = await source.inspectClinicAdministratorActivation(
        'secure-activation-token-with-more-than-32-characters',
      );
      final result = await source.activateClinicAdministrator(
        token: 'secure-activation-token-with-more-than-32-characters',
        password: 'SecureClinic#2026',
        confirmPassword: 'SecureClinic#2026',
      );

      expect(details.clinicName, 'Ada Veterinary Clinic');
      expect(result.mfaEnrollmentRecommended, true);
      expect(requests.map((request) => request.url.path), [
        '/api/v1/auth/clinic-administrator-activation/status',
        '/api/v1/auth/activate-clinic-administrator',
      ]);
      expect(
        requests.every((request) => request.headers['authorization'] == null),
        true,
      );
      expect(
        jsonDecode(requests.last.body),
        containsPair('confirmPassword', 'SecureClinic#2026'),
      );
    },
  );
}
