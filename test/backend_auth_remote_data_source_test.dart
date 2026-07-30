import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/backend_auth_remote_data_source.dart';
import 'package:avera/core/remote/auth_remote_data_source.dart';

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
}
