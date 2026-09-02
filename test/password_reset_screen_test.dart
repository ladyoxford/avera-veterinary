import 'dart:convert';

import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/backend_auth_remote_data_source.dart';
import 'package:avera/core/repositories/authentication_repository.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/authentication/screens/password_reset_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('forgot password renders the email recovery form', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ForgotPasswordScreen(),
        ),
      ),
    );

    expect(find.text('Reset Your Password'), findsOneWidget);
    expect(
      find.text('Enter the email used for registering your clinic.'),
      findsOneWidget,
    );
    expect(find.textContaining('Platform Owner'), findsNothing);
    expect(find.byKey(const Key('forgot-password-email')), findsOneWidget);
    expect(find.byKey(const Key('send-password-reset-link')), findsOneWidget);
    expect(find.textContaining('email recovery is enabled'), findsNothing);
  });

  testWidgets('forgot password treats HTTP 202 as success', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    var requestCount = 0;
    final repository = _repository(
      MockClient((request) async {
        requestCount += 1;
        expect(request.url.path, '/api/v1/auth/forgot-password');
        expect(jsonDecode(request.body), {'email': 'clinic@example.com'});
        return http.Response(
          jsonEncode({'accepted': true}),
          202,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ForgotPasswordScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('forgot-password-email')),
      ' clinic@example.com ',
    );
    await tester.tap(find.byKey(const Key('send-password-reset-link')));
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text(
        'If this email is registered, a password reset link has been sent.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('The AVERA server is unavailable. Please try again shortly.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password preserves genuine server failure', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final repository = _repository(
      MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'service_unavailable'}),
          503,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ForgotPasswordScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('forgot-password-email')),
      'clinic@example.com',
    );
    await tester.tap(find.byKey(const Key('send-password-reset-link')));
    await tester.pumpAndSettle();

    expect(
      find.text('The AVERA server is unavailable. Please try again shortly.'),
      findsOneWidget,
    );
    expect(find.text('Check your email'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('send-password-reset-link')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password validates email before sending', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    var requestCount = 0;
    final repository = _repository(
      MockClient((_) async {
        requestCount += 1;
        return http.Response('{}', 202);
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticationRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ForgotPasswordScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('forgot-password-email')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('send-password-reset-link')));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(requestCount, 0);
  });

  testWidgets('reset password renders secure new-password fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ResetPasswordScreen(token: 'single-use-token'),
        ),
      ),
    );

    expect(find.text('Create New Password'), findsOneWidget);
    expect(find.byKey(const Key('reset-password-new')), findsOneWidget);
    expect(find.byKey(const Key('reset-password-confirm')), findsOneWidget);
    expect(find.byKey(const Key('submit-password-reset')), findsOneWidget);
  });

  testWidgets('reset password rejects an incomplete link', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ResetPasswordScreen(token: ''),
        ),
      ),
    );

    expect(find.text('Reset link unavailable'), findsOneWidget);
    expect(find.text('Request New Link'), findsOneWidget);
    expect(find.byKey(const Key('submit-password-reset')), findsNothing);
  });
}

AuthenticationRepository _repository(http.Client client) {
  const storage = FlutterSecureStorage();
  final tokens = const TokenStore(storage);
  return AuthenticationRepository(
    remote: BackendAuthRemoteDataSource(
      ApiClient(
        baseUrl: 'https://api.avera.test',
        tokens: tokens,
        client: client,
      ),
    ),
    tokens: tokens,
  );
}
