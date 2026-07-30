import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/remote/api_client.dart';
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
      switch (destination) {
        case 'appointmentDetail':
          appRouter.go('/appointments/$id');
        case 'vaccinationRecord':
          appRouter.go('/vaccinations/$id');
        case 'patientDetail':
          appRouter.go('/animals/$id');
        case 'consultationDetail':
          appRouter.go('/consultations/$id');
      }
    } catch (_) {
      // Invalid payloads are ignored rather than navigating with untrusted text.
    }
  }

  @override
  Widget build(BuildContext context) {
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
