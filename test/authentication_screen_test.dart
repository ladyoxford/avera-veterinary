import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/authentication/screens/authentication_screen.dart';
import 'package:avera/features/shared/widgets/avera_auth_ui.dart';

void main() {
  Widget buildSubject({required ThemeData theme}) {
    return ProviderScope(
      overrides: [
        biometricEnrollmentProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(theme: theme, home: const AuthenticationScreen()),
    );
  }

  Future<void> verifyNeutralLogin(
    WidgetTester tester, {
    required ThemeData theme,
  }) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildSubject(theme: theme));
    await tester.pump();

    expect(find.text('AVERA'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      find.text('Sign in to manage your veterinary clinic.'),
      findsOneWidget,
    );
    expect(
      find.text('Sign in to manage Avera Veterinary Clinic'),
      findsNothing,
    );
    expect(find.textContaining('Zevora Veterinary Clinic'), findsNothing);
    expect(find.byType(AveraAuthCard), findsOneWidget);
    expect(find.byKey(const Key('continue-with-google')), findsOneWidget);
    expect(find.byKey(const Key('continue-with-apple')), findsOneWidget);
    expect(find.text('or continue with email'), findsOneWidget);
    expect(find.byKey(const Key('sign-in-email')), findsOneWidget);
    expect(find.byKey(const Key('sign-in-password')), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.byKey(const Key('register-clinic-button')), findsOneWidget);
    expect(
      find.textContaining("Your clinic's data is encrypted and isolated"),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets('pre-login copy is neutral in the light theme', (tester) async {
    await verifyNeutralLogin(tester, theme: AppTheme.light());
  });

  testWidgets('pre-login copy is neutral in the dark theme', (tester) async {
    await verifyNeutralLogin(tester, theme: AppTheme.dark());
  });

  testWidgets('Register Your Clinic opens the registration route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const AuthenticationScreen(),
        ),
        GoRoute(
          path: '/register-clinic',
          builder: (_, __) =>
              const Scaffold(body: Text('Clinic registration destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricEnrollmentProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final register = find.byKey(const Key('register-clinic-button'));
    await tester.ensureVisible(register);
    await tester.tap(register);
    await tester.pumpAndSettle();

    expect(find.text('Clinic registration destination'), findsOneWidget);
  });
}
