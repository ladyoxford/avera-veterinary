import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/screens/backup_screen.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';

void main() {
  Widget subject(ThemeData theme) => ProviderScope(
    child: MaterialApp(theme: theme, home: const BackupScreen()),
  );

  testWidgets('backup actions are independent AVERA cards with a visible gap', (
    tester,
  ) async {
    await tester.pumpWidget(subject(AppTheme.dark()));

    expect(find.byType(AveraAdministrationCard), findsNWidgets(2));
    final export = tester.getRect(find.text('Export SQLite Database'));
    final restore = tester.getRect(find.text('Restore from Backup'));
    expect(restore.top - export.bottom, greaterThan(AveraSpacing.cardGap));
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup screen remains responsive on a narrow light device', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(subject(AppTheme.light()));

    expect(
      find.text('Protect and recover your clinic’s local records.'),
      findsOneWidget,
    );
    expect(find.textContaining('Select a valid AVERA backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
