import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../database/app_database.dart';
import '../models/reminder_event.dart';
import '../repositories/clinic_repository.dart';

/// Bridges an Android notification tap into the running Flutter navigation
/// tree. Payloads contain only clinic-scoped record identifiers, never patient
/// contact information or authentication material.
class NotificationTapDispatcher {
  NotificationTapDispatcher._();

  static final _controller = StreamController<String>.broadcast();
  static Stream<String> get payloads => _controller.stream;

  static void dispatch(String? payload) {
    if (payload != null && payload.isNotEmpty) _controller.add(payload);
  }
}

/// Schedules only on-device reminders. Patient contact details never leave the
/// device and this service deliberately does not claim to send SMS or email.
abstract interface class AppointmentNotificationService {
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<void> scheduleReminder({
    required AppointmentDetail detail,
    required AppointmentReminder reminder,
    required String timeZone,
  });
  Future<void> cancelReminder(int notificationId);
  Future<void> cancelReminders(Iterable<AppointmentReminder> reminders);
  Future<void> reconcileEvents({
    required Iterable<ReminderEvent> events,
    required String timeZone,
  });
}

class LocalAppointmentNotificationService
    implements AppointmentNotificationService {
  LocalAppointmentNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  bool get _supportsNotifications =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<void> initialize() async {
    if (_initialized || !_supportsNotifications) return;
    tz.initializeTimeZones();
    try {
      final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone.identifier));
    } catch (_) {
      // The timezone package has a UTC fallback. A clinic timezone is set
      // explicitly before each schedule attempt below.
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_avera'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        NotificationTapDispatcher.dispatch(response.payload);
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      NotificationTapDispatcher.dispatch(
        launchDetails?.notificationResponse?.payload,
      );
    }
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supportsNotifications) return false;
    await initialize();
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> scheduleReminder({
    required AppointmentDetail detail,
    required AppointmentReminder reminder,
    required String timeZone,
  }) async {
    if (!_supportsNotifications || !reminder.enabled) return;
    final scheduledFor = reminder.scheduledFor;
    if (scheduledFor == null || !scheduledFor.isAfter(DateTime.now())) return;
    await initialize();
    tz.Location location;
    try {
      location = tz.getLocation(timeZone);
    } catch (_) {
      location = tz.local;
    }
    final patientName = detail.animal.animalName;
    final appointmentType = detail.appointment.purpose;
    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      title: 'AVERA appointment reminder',
      body:
          '$patientName: $appointmentType is in ${reminder.daysBefore} day${reminder.daysBefore == 1 ? '' : 's'}.',
      scheduledDate: tz.TZDateTime.from(scheduledFor, location),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'avera_appointment_reminders',
          'Appointment reminders',
          channelDescription:
              'On-device reminders for scheduled clinic visits.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode({
        'destinationType': 'appointmentDetail',
        'appointmentId': detail.appointment.id,
        'clinicId': detail.appointment.clinicId,
      }),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelReminder(int notificationId) async {
    if (!_supportsNotifications) return;
    await initialize();
    await _plugin.cancel(id: notificationId);
  }

  @override
  Future<void> cancelReminders(Iterable<AppointmentReminder> reminders) async {
    for (final reminder in reminders) {
      await cancelReminder(reminder.notificationId);
    }
  }

  @override
  Future<void> reconcileEvents({
    required Iterable<ReminderEvent> events,
    required String timeZone,
  }) async {
    if (!_supportsNotifications) return;
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    final now = DateTime.now();
    final desired = <int, (ReminderEvent, DateTime)>{};
    for (final event in events) {
      if (event.notificationDismissed) continue;
      final reminderTime = event.reminderAt?.isAfter(now) == true
          ? event.reminderAt
          : event.scheduledAt.isAfter(now)
          ? event.scheduledAt
          : null;
      if (reminderTime != null) {
        desired[stableReminderNotificationId(event.eventId)] = (
          event,
          reminderTime,
        );
      }
    }
    for (final request in pending.where(
      (item) => item.payload?.contains('"reminderEventId"') == true,
    )) {
      if (!desired.containsKey(request.id)) {
        await _plugin.cancel(id: request.id);
      }
    }
    tz.Location location;
    try {
      location = tz.getLocation(timeZone);
    } catch (_) {
      location = tz.local;
    }
    for (final entry in desired.entries) {
      final event = entry.value.$1;
      final reminderTime = entry.value.$2;
      await _plugin.zonedSchedule(
        id: entry.key,
        title: event.title,
        body: [
          event.patientName,
          event.description,
        ].where((value) => value?.trim().isNotEmpty == true).join(': '),
        scheduledDate: tz.TZDateTime.from(reminderTime, location),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'avera_clinical_reminders',
            'Clinical reminders',
            channelDescription:
                'Appointments, vaccinations, surgeries and treatments due.',
            icon: 'ic_stat_avera',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode({
          'reminderEventId': event.eventId,
          if (event.notificationId != null)
            'notificationId': event.notificationId,
          'destinationType': event.relatedEntityType,
          'entityId': event.relatedEntityId,
          'module': event.module,
          if (event.patientId != null) 'patientId': event.patientId,
        }),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

int stableReminderNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

class NoopAppointmentNotificationService
    implements AppointmentNotificationService {
  const NoopAppointmentNotificationService();

  @override
  Future<void> cancelReminder(int notificationId) async {}

  @override
  Future<void> cancelReminders(Iterable<AppointmentReminder> reminders) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleReminder({
    required AppointmentDetail detail,
    required AppointmentReminder reminder,
    required String timeZone,
  }) async {}

  @override
  Future<void> reconcileEvents({
    required Iterable<ReminderEvent> events,
    required String timeZone,
  }) async {}
}
