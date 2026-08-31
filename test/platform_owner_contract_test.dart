import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Platform Owner shell keeps exactly five canonical destinations', () {
    final source = File(
      'lib/features/administration/widgets/platform_owner_shell.dart',
    ).readAsStringSync();
    final destinations = source.substring(
      source.indexOf('static const _destinations'),
      source.indexOf('@override', source.indexOf('static const _destinations')),
    );

    expect(
      RegExp(r'_PlatformDestination\(').allMatches(destinations),
      hasLength(5),
    );
    for (final label in [
      'Overview',
      'Clinics',
      'Subscriptions',
      'Operations',
      'Account',
    ]) {
      expect(destinations, contains("label: '$label'"));
    }
    expect(source, contains("path.startsWith('/platform/mfa')"));
  });

  test(
    'Platform Owner controls use canonical routes and safe audit details',
    () {
      final dashboard = File(
        'lib/features/administration/screens/functional_platform_dashboard.dart',
      ).readAsStringSync();
      final management = File(
        'lib/features/administration/screens/platform_management_screens.dart',
      ).readAsStringSync();

      expect(dashboard, contains("route: '/platform/announcements'"));
      expect(
        management,
        contains('onTap: () => _showAuditDetails(context, log)'),
      );
      for (final field in [
        "label: 'Action'",
        "label: 'Date'",
        "label: 'Actor'",
        "label: 'Target'",
        "label: 'Clinic'",
        "label: 'Result'",
        "label: 'Previous'",
        "label: 'New'",
      ]) {
        expect(management, contains(field));
      }
      expect(management, contains("'password'"));
      expect(management, contains("'secret'"));
      expect(management, contains("'token'"));
      expect(management, contains("title: 'Payment provider'"));
    },
  );
}
