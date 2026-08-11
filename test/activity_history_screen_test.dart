import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/screens/activity_history_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Activity History uses one page title and an external module label',
    (tester) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ActivityHistoryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Activity History'), findsOneWidget);
      expect(find.text('MODULE'), findsOneWidget);
      expect(find.text('Module'), findsNothing);
      expect(find.text('All Modules'), findsOneWidget);
      expect(find.byKey(const Key('activity-module-filter')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets('Activity History filter follows the AVERA theme', (
      tester,
    ) async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(theme: theme, home: const ActivityHistoryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dropdown = tester.widget<DropdownButton<String?>>(
        find.byKey(const Key('activity-module-filter')),
      );
      expect(dropdown.style?.color, theme.colorScheme.onSurface);
      expect(tester.takeException(), isNull);
    });
  }
}
