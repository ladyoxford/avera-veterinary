import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/remote/api_client.dart';
import 'core/remote/cloud_clinical_state.dart';
import 'core/router/app_router.dart';
import 'core/config/app_providers.dart';
import 'core/database/database_restore_coordinator.dart';
import 'core/services/appointment_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackendConfiguration.validate();
  await DatabaseRestoreCoordinator.applyPendingRestore();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const AveraApp(),
    ),
  );
}

class AveraApp extends ConsumerStatefulWidget {
  const AveraApp({super.key});

  @override
  ConsumerState<AveraApp> createState() => _AveraAppState();
}

class _AveraAppState extends ConsumerState<AveraApp> {
  StreamSubscription<String>? _notificationTapSubscription;
  StreamSubscription<void>? _accountRestrictionSubscription;

  @override
  void initState() {
    super.initState();
    _notificationTapSubscription = NotificationTapDispatcher.payloads.listen(
      _openNotificationPayload,
    );
    _accountRestrictionSubscription = AccountRestrictionDispatcher.events
        .listen((_) {
          ref.invalidate(userSessionProvider);
          appRouter.go('/account-restricted');
        });
    unawaited(ref.read(appointmentNotificationServiceProvider).initialize());
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    _accountRestrictionSubscription?.cancel();
    super.dispose();
  }

  void _openNotificationPayload(String payload) {
    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final destination = decoded['destinationType'] as String?;
      final id = decoded['appointmentId'] ?? decoded['entityId'];
      if (id == null) return;
      final notificationId = decoded['notificationId']?.toString();
      if (notificationId != null && notificationId.isNotEmpty) {
        unawaited(_markRemoteNotificationRead(notificationId));
      }
      switch (destination) {
        case 'appointmentDetail' || 'Schedule':
          appRouter.go('/appointments/$id');
        case 'vaccinationRecord' || 'Vaccination':
          appRouter.go('/vaccinations/$id');
        case 'patientDetail' || 'Patient':
          appRouter.go('/animals/$id');
        case 'consultationDetail' || 'Consultation':
          appRouter.go('/consultations/$id');
        case 'ClinicalOperation':
          final module = decoded['module']?.toString().toLowerCase();
          final path = switch (module) {
            'surgery' => '/operations/surgery',
            'treatment' => '/operations/treatment-board',
            _ => null,
          };
          if (path != null) appRouter.go('$path?recordId=$id&direct=true');
      }
    } catch (_) {
      // Invalid payloads are ignored rather than navigating with untrusted text.
    }
  }

  Future<void> _markRemoteNotificationRead(String notificationId) async {
    if (!BackendConfiguration.isConfigured) return;
    try {
      await ref
          .read(apiClientProvider)
          .patch('/api/v1/notifications/$notificationId/read');
    } catch (_) {
      // The exact record still opens; the inbox can retry its read state later.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(userSessionProvider, (_, next) {
      final session = next.valueOrNull;
      if (!BackendConfiguration.isConfigured || session == null) return;
      Future<void>(() async {
        try {
          final feed = await ref
              .read(clinicalRemoteDataSourceProvider)
              .reminders();
          final service = ref.read(appointmentNotificationServiceProvider);
          await service.requestPermission();
          await service.reconcileEvents(
            events: feed.upcoming,
            timeZone: session.clinic.timeZone,
          );
          ref.invalidate(remoteReminderFeedProvider);
          ref.invalidate(remoteNotificationsProvider);
        } catch (_) {
          // Dashboard refresh and the next authenticated launch retry this sync.
        }
      });
    });
    final themeMode = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: child ?? const SizedBox.shrink(),
        breakpoints: const [
          Breakpoint(start: 0, end: 599, name: MOBILE),
          Breakpoint(start: 600, end: 1023, name: TABLET),
          Breakpoint(start: 1024, end: double.infinity, name: DESKTOP),
        ],
      ),
    );
  }
}
