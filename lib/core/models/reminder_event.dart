class ReminderEvent {
  const ReminderEvent({
    required this.eventId,
    required this.eventType,
    required this.module,
    required this.relatedEntityType,
    required this.relatedEntityId,
    required this.patientId,
    required this.patientName,
    required this.title,
    required this.description,
    required this.scheduledAt,
    required this.reminderAt,
    required this.priority,
    required this.status,
    this.notificationId,
    this.notificationDismissed = false,
  });

  final String eventId;
  final String eventType;
  final String module;
  final String relatedEntityType;
  final String relatedEntityId;
  final String? patientId;
  final String? patientName;
  final String title;
  final String description;
  final DateTime scheduledAt;
  final DateTime? reminderAt;
  final String priority;
  final String status;
  final String? notificationId;
  final bool notificationDismissed;

  factory ReminderEvent.fromJson(Map<String, dynamic> value) => ReminderEvent(
    eventId: '${value['event_id']}',
    eventType: '${value['event_type']}',
    module: '${value['module']}',
    relatedEntityType: '${value['related_entity_type']}',
    relatedEntityId: '${value['related_entity_id']}',
    patientId: _optionalText(value['patient_id']),
    patientName: _optionalText(value['patient_name']),
    title: '${value['title']}',
    description: '${value['description'] ?? ''}',
    scheduledAt: DateTime.parse('${value['scheduled_at']}').toLocal(),
    reminderAt: DateTime.tryParse('${value['reminder_at']}')?.toLocal(),
    priority: '${value['priority']}',
    status: '${value['status']}',
    notificationId: _optionalText(value['notification_id']),
    notificationDismissed: value['notification_dismissed'] == true,
  );

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'event_type': eventType,
    'module': module,
    'related_entity_type': relatedEntityType,
    'related_entity_id': relatedEntityId,
    'patient_id': patientId,
    'patient_name': patientName,
    'title': title,
    'description': description,
    'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    'reminder_at': reminderAt?.toUtc().toIso8601String(),
    'priority': priority,
    'status': status,
    'notification_id': notificationId,
    'notification_dismissed': notificationDismissed,
  };
}

class ReminderFeed {
  const ReminderFeed({required this.upcoming, required this.alerts});

  final List<ReminderEvent> upcoming;
  final List<ReminderEvent> alerts;

  factory ReminderFeed.fromJson(Map<String, dynamic> value) => ReminderFeed(
    upcoming: _events(value['upcoming']),
    alerts: _events(value['alerts']),
  );

  Map<String, dynamic> toJson() => {
    'upcoming': upcoming.map((item) => item.toJson()).toList(),
    'alerts': alerts.map((item) => item.toJson()).toList(),
  };
}

class RemoteNotificationItem {
  const RemoteNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.priority,
    required this.relatedEntityType,
    required this.relatedEntityId,
    required this.patientId,
    required this.scheduledAt,
    required this.createdAt,
    required this.readAt,
    required this.eventId,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String priority;
  final String relatedEntityType;
  final String relatedEntityId;
  final String? patientId;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final DateTime? readAt;
  final String eventId;

  bool get isRead => readAt != null;

  factory RemoteNotificationItem.fromJson(Map<String, dynamic> value) =>
      RemoteNotificationItem(
        id: '${value['notification_id']}',
        type: '${value['notification_type']}',
        title: '${value['title']}',
        body: '${value['body']}',
        priority: '${value['priority']}',
        relatedEntityType: '${value['related_entity_type']}',
        relatedEntityId: '${value['related_entity_id']}',
        patientId: _optionalText(value['patient_id']),
        scheduledAt: DateTime.tryParse('${value['scheduled_at']}')?.toLocal(),
        createdAt: DateTime.parse('${value['created_at']}').toLocal(),
        readAt: DateTime.tryParse('${value['read_at']}')?.toLocal(),
        eventId: '${value['event_id']}',
      );

  Map<String, dynamic> toJson() => {
    'notification_id': id,
    'notification_type': type,
    'title': title,
    'body': body,
    'priority': priority,
    'related_entity_type': relatedEntityType,
    'related_entity_id': relatedEntityId,
    'patient_id': patientId,
    'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'read_at': readAt?.toUtc().toIso8601String(),
    'event_id': eventId,
  };
}

List<ReminderEvent> _events(Object? value) =>
    (value as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ReminderEvent.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}
