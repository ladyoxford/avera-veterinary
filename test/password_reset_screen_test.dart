import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/authentication/screens/password_reset_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.byKey(const Key('forgot-password-email')), findsOneWidget);
    expect(find.byKey(const Key('send-password-reset-link')), findsOneWidget);
    expect(find.textContaining('email recovery is enabled'), findsNothing);
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
