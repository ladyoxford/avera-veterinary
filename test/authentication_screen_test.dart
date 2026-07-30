import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/authentication/screens/authentication_screen.dart';

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
    expect(tester.takeException(), isNull);
  }

  testWidgets('pre-login copy is neutral in the light theme', (tester) async {
    await verifyNeutralLogin(tester, theme: AppTheme.light());
  });

  testWidgets('pre-login copy is neutral in the dark theme', (tester) async {
    await verifyNeutralLogin(tester, theme: AppTheme.dark());
  });
}
