import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/administration/screens/staff_management_screen.dart';

void main() {
  test('only active clinic administrators can add staff', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final administrator = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    expect(administrator, isNot(equals(null)));

    expect(
      staffManagementCanAddUser(administrator!, StaffManagementTab.active),
      isTrue,
    );
    for (final tab in StaffManagementTab.values.skip(1)) {
      expect(staffManagementCanAddUser(administrator, tab), isFalse);
    }

    final veterinarian = UserSession(
      user: administrator.user.copyWith(
        role: 'Veterinarian',
        accountType: AccountTypes.clinicStaff,
      ),
      clinic: administrator.clinic,
    );
    expect(
      staffManagementCanAddUser(veterinarian, StaffManagementTab.active),
      isFalse,
    );
  });

  for (final size in [
    const Size(320, 640),
    const Size(360, 800),
    const Size(393, 873),
  ]) {
    testWidgets('former staff dialog fits at ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FormerStaffDetailsDialog(),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Former Staff Details'), findsOneWidget);
      expect(find.text('Removal reason'), findsOneWidget);
      expect(find.text('Optional note'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('former staff dialog supports increased text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const Scaffold(body: FormerStaffDetailsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
