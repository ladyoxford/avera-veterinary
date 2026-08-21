import 'package:avera/features/billing/widgets/payment_capture_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captures amount, method, and optional reference', (
    tester,
  ) async {
    PaymentCapture? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showPaymentCaptureDialog(
                  context: context,
                  outstanding: 32000,
                  currency: 'NGN',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Outstanding: NGN 32000.00'), findsOneWidget);

    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer').last);
    await tester.enterText(
      find.widgetWithText(TextField, 'Optional reference'),
      'TRX-2026-001',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Record Payment'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.amount, 32000);
    expect(result!.method, 'Transfer');
    expect(result!.reference, 'TRX-2026-001');
  });

  testWidgets('rejects an amount above the outstanding balance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showPaymentCaptureDialog(
                context: context,
                outstanding: 5000,
                currency: 'NGN',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount received'),
      '5001',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Record Payment'));
    await tester.pump();

    expect(
      find.text('The payment cannot exceed the outstanding balance.'),
      findsOneWidget,
    );
  });
}
