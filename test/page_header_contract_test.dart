import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pushed pages do not repeat their app-bar title in the body', () {
    final farm = File(
      'lib/features/farm/screens/farm_profile_editor_screen.dart',
    ).readAsStringSync();
    final reports = File(
      'lib/features/reports/screens/reports_screen.dart',
    ).readAsStringSync();
    final consultation = File(
      'lib/features/consultation/screens/consultation_screen.dart',
    ).readAsStringSync();

    final farmBody = farm.substring(
      farm.indexOf('Widget build(BuildContext context) => Scaffold'),
      farm.indexOf('Widget _textField'),
    );
    expect(farmBody, isNot(contains('AveraPageHeader(')));

    final reportsList = reports.substring(
      reports.indexOf('class ReportsScreen'),
      reports.indexOf('class ReportDetailScreen'),
    );
    expect(reportsList, isNot(contains("title: 'Reports'")));

    final consultationForm = consultation.substring(
      consultation.indexOf('class _ConsultationForm'),
      consultation.indexOf('class _ConsultationFieldCard'),
    );
    expect(consultationForm, isNot(contains('AveraPageHeader(')));
  });

  test('root pages own one body header and Schedule is safe-area aware', () {
    final more = File(
      'lib/features/shared/screens/clinic_operations_screens.dart',
    ).readAsStringSync();
    final schedule = File(
      'lib/features/shared/screens/appointments_screen.dart',
    ).readAsStringSync();

    final moreScreen = more.substring(
      more.indexOf('class MoreScreen'),
      more.indexOf('class ClinicVaccineScheduleScreen'),
    );
    expect(moreScreen, contains("title: 'More'"));
    expect(
      moreScreen,
      isNot(contains("appBar: AppBar(title: const Text('More'))")),
    );

    final scheduleScreen = schedule.substring(
      schedule.indexOf('class AppointmentsScreen'),
      schedule.indexOf('class AppointmentDetailScreen'),
    );
    expect(scheduleScreen, contains('SafeArea('));
    expect(scheduleScreen, contains('bottom: false'));
  });
}
