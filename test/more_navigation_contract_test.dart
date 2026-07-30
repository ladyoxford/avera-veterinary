import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('More catalogue contains only canonical destinations', () {
    final source = File(
      'lib/features/shared/screens/clinic_operations_screens.dart',
    ).readAsStringSync();
    final catalogue = source.substring(
      source.indexOf('const _services'),
      source.indexOf('bool _isFeatureLocked'),
    );

    for (final required in [
      'Surgery',
      'Prescriptions',
      'Imaging',
      'Medical Documents',
      'Treatment Board',
      'Farm Records',
      'Expired Products',
      'Administration',
      'Backup & Restore',
    ]) {
      expect(catalogue, contains("'$required'"));
    }
    for (final removed in [
      'Vaccine Schedule',
      'Laboratory',
      'Hospitalization',
      'Inventory',
      'Billing',
      'Reports',
      'Schedule',
      'Notifications',
      'Users',
      'Client Engagement',
      'Pinned Services',
    ]) {
      expect(catalogue, isNot(contains("'$removed'")));
    }
    expect(catalogue, contains('/inventory?filter=expired'));
  });

  test('Clinic Administration overview does not own Invite User FAB', () {
    final source = File(
      'lib/features/administration/screens/administration_screens.dart',
    ).readAsStringSync();
    final overview = source.substring(
      source.indexOf('class ClinicAdministrationScreen'),
      source.indexOf('class ClinicUserManagementScreen'),
    );
    expect(overview, isNot(contains('Invite User')));
    expect(overview, isNot(contains('floatingActionButton')));
  });
}
