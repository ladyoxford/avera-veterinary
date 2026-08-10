import 'package:flutter_test/flutter_test.dart';

import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/features/shared/navigation/clinic_activity_navigation.dart';
import 'package:avera/features/shared/screens/dashboard_screen.dart';

void main() {
  test('maps production summary into the original dashboard model', () {
    final summary = RemoteDashboardSummary.fromJson({
      'registered_patients': 12,
      'todays_schedule': 3,
      'active_consultations': 2,
      'vaccinations_due': 4,
      'low_stock': 5,
      'expired_products': 1,
      'active_hospitalizations': 2,
      'pending_laboratory_reports': 6,
      'outstanding_invoices': 12000,
      'current_revenue': 54000.5,
      'recentActivity': [
        {
          'type': 'Consultation',
          'record_id': 'consultation-1',
          'patient_id': 'patient-1',
          'summary': 'Annual wellness examination',
          'occurred_at': '2026-08-01T09:30:00.000Z',
        },
      ],
    });

    final stats = dashboardStatsFromRemote(summary, clinicId: 'clinic-1');

    expect(stats.totalAnimals, 12);
    expect(stats.appointmentsToday, 3);
    expect(stats.todaysConsultations, 2);
    expect(stats.vaccinationsDue, 4);
    expect(stats.lowStock, 5);
    expect(stats.expiredDrugs, 1);
    expect(stats.monthlyRevenue, 54000.5);
    expect(stats.recentVisits, isEmpty);
    expect(stats.recentActivity, hasLength(1));
    expect(stats.recentActivity.single.clinicId, 'clinic-1');
    expect(stats.recentActivity.single.title, 'Annual wellness examination');
    expect(stats.recentActivity.single.relatedEntityType, 'Consultation');
    expect(stats.recentActivity.single.relatedEntityId, 'consultation-1');
    expect(stats.recentActivity.single.remotePatientId, 'patient-1');
  });

  test('preserves genuine production zero and empty states', () {
    final summary = RemoteDashboardSummary.fromJson(const {});

    final stats = dashboardStatsFromRemote(summary, clinicId: 'new-clinic');

    expect(stats.totalAnimals, 0);
    expect(stats.todaysConsultations, 0);
    expect(stats.appointmentsToday, 0);
    expect(stats.vaccinationsDue, 0);
    expect(stats.lowStock, 0);
    expect(stats.expiredDrugs, 0);
    expect(stats.monthlyRevenue, 0);
    expect(stats.recentActivity, isEmpty);
    expect(stats.recentVisits, isEmpty);
  });

  test('maps schedule activity to its exact appointment entity', () {
    final summary = RemoteDashboardSummary.fromJson({
      'recentActivity': [
        {
          'type': 'Schedule',
          'record_id': '92a4ce80-f37d-4d87-9293-5525fcc46493',
          'patient_id': 'cb159739-c0cb-4503-a069-9d64563f47bc',
          'summary': 'Grooming',
          'occurred_at': '2026-08-09T22:33:48.672Z',
        },
      ],
    });

    final event = dashboardStatsFromRemote(
      summary,
      clinicId: 'clinic-1',
    ).recentActivity.single;

    expect(event.relatedEntityType, 'Appointment');
    expect(event.relatedEntityId, '92a4ce80-f37d-4d87-9293-5525fcc46493');
    expect(event.remotePatientId, 'cb159739-c0cb-4503-a069-9d64563f47bc');
    expect(
      clinicActivityRoute(event),
      '/appointments/92a4ce80-f37d-4d87-9293-5525fcc46493',
    );
  });
}
