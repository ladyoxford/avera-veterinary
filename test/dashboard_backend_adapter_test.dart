import 'package:flutter_test/flutter_test.dart';

import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/features/shared/screens/dashboard_screen.dart';
import 'package:avera/features/shared/navigation/clinic_activity_navigation.dart';

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

  test('production Schedule activity deep-links to its exact appointment', () {
    const appointmentId = '7925f06b-75d4-4e8a-9ef6-e80b8f28d238';
    final summary = RemoteDashboardSummary.fromJson({
      'recentActivity': [
        {
          'type': 'Schedule',
          'record_id': appointmentId,
          'patient_id': 'patient-1',
          'summary': 'Grooming',
          'occurred_at': '2026-08-10T10:00:00.000Z',
        },
      ],
    });
    final event = dashboardStatsFromRemote(
      summary,
      clinicId: 'clinic-1',
    ).recentActivity.single;

    expect(event.relatedEntityType, 'Schedule');
    expect(clinicActivityRoute(event), '/appointments/$appointmentId');
    expect(
      remoteDashboardActivityRoute(summary.recentActivity.single),
      '/appointments/$appointmentId',
    );
  });

  const operationRoutes = <String, String>{
    'Surgery': '/operations/surgery',
    'Prescription': '/operations/prescriptions',
    'Imaging': '/operations/imaging',
    'Document': '/operations/documents',
    'Treatment': '/operations/treatment-board',
  };

  for (final entry in operationRoutes.entries) {
    test('production ${entry.key} activity deep-links to its exact record', () {
      const operationId = '2656ae09-8248-4934-a6c6-b7eb3f4e2152';
      final summary = RemoteDashboardSummary.fromJson({
        'recentActivity': [
          {
            'type': 'ClinicalOperation',
            'module': entry.key,
            'related_entity_type': 'ClinicalOperation',
            'record_id': operationId,
            'patient_id': 'patient-1',
            'title': '${entry.key} title',
            'summary': '${entry.key} - Scheduled',
            'occurred_at': '2026-08-10T10:00:00.000Z',
          },
        ],
      });
      final event = dashboardStatsFromRemote(
        summary,
        clinicId: 'clinic-1',
      ).recentActivity.single;

      expect(event.module, entry.key.toLowerCase());
      expect(event.title, '${entry.key} title');
      expect(
        clinicActivityRoute(event),
        '${entry.value}?recordId=$operationId&direct=true',
      );
      expect(
        remoteDashboardActivityRoute(summary.recentActivity.single),
        '${entry.value}?recordId=$operationId&direct=true',
      );
    });
  }
}
