import 'package:flutter_test/flutter_test.dart';

import 'package:avera/core/models/reminder_event.dart';
import 'package:avera/core/services/appointment_notification_service.dart';
import 'package:avera/features/shared/navigation/clinic_activity_navigation.dart';

void main() {
  const appointmentId = 'd7e0fd8d-7a69-4a5f-b15b-15eefc57a607';
  const patientId = '5ea89095-e2b3-4a6b-bb65-29d281d53e57';

  Map<String, dynamic> eventJson({
    String eventId = 'appointment:$appointmentId',
    String eventType = 'Appointment',
    String module = 'Schedule',
    String relatedEntityType = 'Schedule',
    String relatedEntityId = appointmentId,
    String? patient = patientId,
  }) => {
    'event_id': eventId,
    'event_type': eventType,
    'module': module,
    'related_entity_type': relatedEntityType,
    'related_entity_id': relatedEntityId,
    'patient_id': patient,
    'patient_name': 'Luna',
    'title': 'Vaccination visit',
    'description': 'Rabies booster',
    'scheduled_at': '2026-08-14T09:30:00.000Z',
    'reminder_at': '2026-08-14T08:30:00.000Z',
    'priority': 'upcoming',
    'status': 'Confirmed',
    'notification_id': '1edc7682-ec1b-405b-9d1a-9782315177eb',
  };

  test('reminder feed preserves chronological event and destination data', () {
    final feed = ReminderFeed.fromJson({
      'upcoming': [eventJson()],
      'alerts': <dynamic>[],
    });

    expect(feed.upcoming, hasLength(1));
    final event = feed.upcoming.single;
    expect(event.eventId, 'appointment:$appointmentId');
    expect(event.patientId, patientId);
    expect(event.scheduledAt.toUtc(), DateTime.utc(2026, 8, 14, 9, 30));
    expect(
      remoteDashboardActivityRoute({
        'related_entity_type': event.relatedEntityType,
        'record_id': event.relatedEntityId,
        'patient_id': event.patientId,
        'module': event.module,
      }),
      '/appointments/$appointmentId',
    );
  });

  test(
    'remote notification read state and exact clinical route are decoded',
    () {
      final item = RemoteNotificationItem.fromJson({
        'notification_id': '1edc7682-ec1b-405b-9d1a-9782315177eb',
        'notification_type': 'Surgery',
        'title': 'Surgery due',
        'body': 'Luna: procedure is due',
        'priority': 'due',
        'related_entity_type': 'ClinicalOperation',
        'related_entity_id': appointmentId,
        'patient_id': patientId,
        'scheduled_at': '2026-08-14T09:30:00.000Z',
        'created_at': '2026-08-12T09:30:00.000Z',
        'read_at': '2026-08-12T10:00:00.000Z',
        'event_id': 'surgery:$appointmentId',
      });

      expect(item.isRead, isTrue);
      expect(
        remoteDashboardActivityRoute({
          'related_entity_type': item.relatedEntityType,
          'record_id': item.relatedEntityId,
          'patient_id': item.patientId,
          'module': item.type,
        }),
        '/operations/surgery?recordId=$appointmentId&direct=true',
      );
    },
  );

  test('stable reminder IDs deduplicate the same event', () {
    final first = stableReminderNotificationId('appointment:$appointmentId');
    final duplicate = stableReminderNotificationId(
      'appointment:$appointmentId',
    );
    final different = stableReminderNotificationId(
      'vaccination:$appointmentId',
    );

    expect(first, duplicate);
    expect(first, isNot(different));
    expect(first, greaterThan(0));
  });

  test('dismissed reminder state survives cache serialization', () {
    final json = eventJson()..['notification_dismissed'] = true;
    final event = ReminderEvent.fromJson(json);

    expect(event.notificationDismissed, isTrue);
    expect(event.toJson()['notification_dismissed'], isTrue);
  });
}
