import 'dart:convert';

import 'package:avera/core/config/backend_configuration.dart';
import 'package:avera/core/services/backend_health_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('backend environment resolution', () {
    test('debug defaults to local and accepts a development URL override', () {
      expect(
        BackendConfiguration.resolveDataMode(
          isRelease: false,
          definedMode: '',
          definedApiBaseUrl: '',
        ),
        AveraDataMode.local,
      );
      expect(
        BackendConfiguration.resolveDataMode(
          isRelease: false,
          definedMode: '',
          definedApiBaseUrl: 'http://10.0.2.2:8080',
        ),
        AveraDataMode.backend,
      );
      expect(
        BackendConfiguration.resolveApiBaseUrl(
          isRelease: false,
          definedApiBaseUrl: 'http://10.0.2.2:8080/',
        ),
        'http://10.0.2.2:8080',
      );
    });

    test('release defaults to the Render production API', () {
      expect(
        BackendConfiguration.resolveDataMode(
          isRelease: true,
          definedMode: '',
          definedApiBaseUrl: '',
        ),
        AveraDataMode.backend,
      );
      expect(
        BackendConfiguration.resolveApiBaseUrl(
          isRelease: true,
          definedApiBaseUrl: '',
        ),
        BackendConfiguration.productionApiBaseUrl,
      );
    });

    test('release rejects insecure and private backend URLs', () {
      for (final value in [
        'http://avera-api-8akc.onrender.com',
        'https://localhost:8080',
        'https://10.0.2.2:8080',
        'https://192.168.1.7:8080',
      ]) {
        expect(
          () => BackendConfiguration.validateResolved(
            isRelease: true,
            mode: AveraDataMode.backend,
            apiBaseUrl: value,
            localDevelopmentAuthEnabled: false,
          ),
          throwsStateError,
        );
      }
    });

    test('normalization and endpoint resolution avoid duplicate slashes', () {
      expect(
        BackendConfiguration.normalizeBaseUrl(
          ' https://avera-api-8akc.onrender.com/// ',
        ),
        BackendConfiguration.productionApiBaseUrl,
      );
      expect(
        BackendConfiguration.resolveEndpoint(
          '${BackendConfiguration.productionApiBaseUrl}/',
          '/api/v1/patients',
        ).toString(),
        '${BackendConfiguration.productionApiBaseUrl}/api/v1/patients',
      );
    });

    test('the public production configuration contains no credentials', () {
      final uri = Uri.parse(BackendConfiguration.productionApiBaseUrl);
      expect(uri.scheme, 'https');
      expect(uri.userInfo, isEmpty);
      expect(uri.query, isEmpty);
      expect(uri.fragment, isEmpty);
    });
  });

  group('startup cloud health', () {
    test('accepts the requested live health response', () async {
      final service = BackendHealthService(
        baseUrl: BackendConfiguration.productionApiBaseUrl,
        client: MockClient((request) async {
          expect(request.url.path, '/health');
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response(jsonEncode({'status': 'live'}), 200);
        }),
      );

      final result = await service.check();
      expect(result.status, CloudConnectivityStatus.online);
      expect(result.serverStatus, 'live');
    });

    test('falls back to the deployed live probe after a root 404', () async {
      final paths = <String>[];
      final service = BackendHealthService(
        baseUrl: '${BackendConfiguration.productionApiBaseUrl}/',
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/health') {
            return http.Response('{}', 404);
          }
          return http.Response(jsonEncode({'status': 'live'}), 200);
        }),
      );

      final result = await service.check();
      expect(result.status, CloudConnectivityStatus.online);
      expect(paths, ['/health', '/health/live']);
    });

    test(
      'a slow health endpoint yields waking without blocking startup',
      () async {
        final stopwatch = Stopwatch()..start();
        final service = BackendHealthService(
          baseUrl: BackendConfiguration.productionApiBaseUrl,
          timeout: const Duration(milliseconds: 30),
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(seconds: 1));
            return http.Response(jsonEncode({'status': 'live'}), 200);
          }),
        );

        final result = await service.check();
        stopwatch.stop();
        expect(result.status, CloudConnectivityStatus.waking);
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 300)));
      },
    );
  });
}
