import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/animals/screens/animal_registration_screen.dart';
import '../../features/animals/screens/animal_search_screen.dart';
import '../../features/animals/screens/archived_animals_screen.dart';
import '../../features/animals/screens/medical_file_hub_screen.dart';
import '../../features/animals/screens/cloud_patient_screens.dart';
import '../remote/api_client.dart';
import '../../features/authentication/screens/authentication_screen.dart';
import '../../features/authentication/screens/clinic_registration_screen.dart';
import '../../features/authentication/screens/clinic_administrator_activation_screen.dart';
import '../../features/authentication/screens/password_reset_screens.dart';
import '../../features/authentication/screens/offline_access_screens.dart';
import '../../features/administration/screens/administration_screens.dart';
import '../../features/administration/screens/platform_management_screens.dart';
import '../../features/administration/screens/functional_platform_dashboard.dart';
import '../../features/administration/screens/subscription_plans_screen.dart';
import '../../features/administration/screens/clinic_work_hours_screen.dart';
import '../../features/billing/screens/billing_screen.dart';
import '../../features/consultation/screens/consultation_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/shared/screens/appointments_screen.dart';
import '../../features/shared/screens/backup_screen.dart';
import '../../features/shared/screens/clinic_operations_screens.dart';
import '../../features/shared/screens/dashboard_screen.dart';
import '../../features/shared/screens/notifications_screen.dart';
import '../../features/shared/screens/settings_screen.dart';
import '../../features/shared/screens/splash_screen.dart';
import '../../features/shared/widgets/app_scaffold.dart';
import '../../features/shared/widgets/feature_gate.dart';
import '../../features/vaccination/screens/vaccination_protocols_screen.dart';
import '../../features/vera/screens/vera_screen.dart';
import '../services/feature_gate_service.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (context, state) => AuthenticationScreen(
        clinicName: state.uri.queryParameters['clinicName'],
      ),
    ),
    GoRoute(
      path: '/offline-unlock',
      builder: (context, state) => const OfflineUnlockScreen(),
    ),
    GoRoute(
      path: '/offline-access',
      builder: (context, state) => const OfflinePinSetupScreen(),
    ),
    GoRoute(
      path: '/register-clinic',
      builder: (context, state) => const ClinicRegistrationScreen(),
    ),
    GoRoute(
      path: '/activate-clinic-admin',
      builder: (context, state) => ClinicAdministratorActivationScreen(
        token: state.uri.queryParameters['token'] ?? '',
      ),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) =>
          ResetPasswordScreen(token: state.uri.queryParameters['token'] ?? ''),
    ),
    GoRoute(
      path: '/platform',
      builder: (context, state) =>
          const FunctionalPlatformOwnerDashboardScreen(),
    ),
    GoRoute(
      path: '/platform/clinics',
      builder: (context, state) =>
          PlatformClinicsScreen(status: state.uri.queryParameters['status']),
    ),
    GoRoute(
      path: '/platform/clinics/:clinicId',
      builder: (context, state) => PlatformClinicDetailScreen(
        clinicId: state.pathParameters['clinicId']!,
      ),
    ),
    GoRoute(
      path: '/platform/subscriptions',
      builder: (context, state) => PlatformSubscriptionsScreen(
        status: state.uri.queryParameters['status'],
      ),
    ),
    GoRoute(
      path: '/platform/revenue',
      builder: (context, state) => const PlatformSubscriptionsScreen(),
    ),
    GoRoute(
      path: '/platform/users',
      builder: (context, state) => const PlatformUsersScreen(),
    ),
    GoRoute(
      path: '/platform/audit',
      builder: (context, state) => const PlatformAuditLogsScreen(),
    ),
    GoRoute(
      path: '/platform/notifications',
      builder: (context, state) => const PlatformUtilityScreen(
        title: 'Platform Notifications',
        message: 'No platform notifications require attention.',
        icon: Icons.notifications_none_rounded,
      ),
    ),
    GoRoute(
      path: '/platform/email',
      builder: (context, state) => const PlatformUtilityScreen(
        title: 'Email Delivery',
        message:
            'Email delivery requires a configured secure provider backend.',
        icon: Icons.email_outlined,
      ),
    ),
    GoRoute(
      path: '/platform/storage',
      builder: (context, state) => const PlatformUtilityScreen(
        title: 'Storage Usage',
        message:
            'Storage reporting will become available after cloud storage is configured.',
        icon: Icons.storage_outlined,
      ),
    ),
    GoRoute(
      path: '/platform/settings',
      builder: (context, state) => const PlatformUtilityScreen(
        title: 'Platform Settings',
        message: 'Global settings are ready for secure backend configuration.',
        icon: Icons.settings_outlined,
      ),
    ),
    GoRoute(
      path: '/platform/developer-settings',
      builder: (context, state) => const PlatformDeveloperSettingsScreen(),
    ),
    GoRoute(
      path: '/platform/password',
      builder: (context, state) => const PlatformPasswordScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => AppScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/subscription',
          builder: (context, state) => const SubscriptionPlansScreen(),
        ),
        GoRoute(
          path: '/subscription/compare',
          builder: (context, state) => const SubscriptionCompareScreen(),
        ),
        GoRoute(path: '/more', builder: (context, state) => const MoreScreen()),
        GoRoute(
          path: '/vera',
          builder: (context, state) => FeatureGate(
            feature: AveraFeature.vera,
            child: VeraScreen(
              patientId: int.tryParse(
                state.uri.queryParameters['patientId'] ?? '',
              ),
              patientName: state.uri.queryParameters['patientName'],
            ),
          ),
        ),
        GoRoute(
          path: '/operations/vaccines',
          builder: (context, state) => const ClinicVaccineScheduleScreen(),
        ),
        GoRoute(
          path: '/operations/laboratory',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.laboratory,
            child: ClinicOperationsPlaceholderScreen(
              title: 'Laboratory',
              description:
                  'Laboratory orders and result persistence will appear here once the clinic laboratory schema is enabled.',
              icon: Icons.science_outlined,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/hospitalization',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.hospitalization,
            child: ClinicOperationsPlaceholderScreen(
              title: 'Hospitalization',
              description:
                  'Clinic-wide admissions and treatment plans will appear here once hospitalization records are enabled.',
              icon: Icons.local_hospital_outlined,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/treatment-board',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.treatmentBoard,
            child: ClinicOperationsPlaceholderScreen(
              title: 'Treatment Board',
              description:
                  'Scheduled treatment tracking will appear here with hospitalization treatment records.',
              icon: Icons.view_kanban_outlined,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/surgery',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.surgery,
            child: ClinicOperationsPlaceholderScreen(
              title: 'Surgery',
              description:
                  'Clinic-wide surgical scheduling will appear here when surgery records are enabled.',
              icon: Icons.medical_services_outlined,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/prescriptions',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.prescriptions,
            child: ClinicOperationsPlaceholderScreen(
              title: 'Prescriptions',
              description:
                  'Clinic-wide prescription dispensing will appear here when prescription records are enabled.',
              icon: Icons.medication_outlined,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/imaging',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.imaging,
            child: ClinicOperationsPlaceholderScreen(
              title: 'Imaging',
              description:
                  'Clinic-wide imaging requests and reports will appear here when imaging records are enabled.',
              icon: Icons.image_search_outlined,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/documents',
          builder: (context, state) => const ClinicOperationsPlaceholderScreen(
            title: 'Medical Documents',
            description:
                'Clinic-wide document management will appear here when document records are enabled.',
            icon: Icons.description_outlined,
          ),
        ),
        GoRoute(
          path: '/animals',
          builder: (context, state) => const AnimalSearchScreen(),
        ),
        GoRoute(
          path: '/animals/archived',
          builder: (context, state) => const ArchivedAnimalsScreen(),
        ),
        GoRoute(
          path: '/animals/new',
          builder: (context, state) => const AnimalRegistrationScreen(),
        ),
        GoRoute(
          path: '/animals/:id',
          builder: (context, state) => BackendConfiguration.isConfigured
              ? CloudPatientMedicalFileScreen(
                  patientId: state.pathParameters['id']!,
                )
              : MedicalFileHubScreen(
                  animalId: int.parse(state.pathParameters['id']!),
                ),
        ),
        GoRoute(
          path: '/consultations/new',
          builder: (context, state) => ConsultationScreen(
            initialAnimalId: int.tryParse(
              state.uri.queryParameters['animalId'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/consultations/:consultationId/edit',
          builder: (context, state) => ConsultationScreen(
            mode: ConsultationScreenMode.edit,
            consultationId: int.parse(state.pathParameters['consultationId']!),
          ),
        ),
        GoRoute(
          path: '/consultations/:consultationId',
          builder: (context, state) => ConsultationScreen(
            mode: ConsultationScreenMode.view,
            consultationId: int.parse(state.pathParameters['consultationId']!),
          ),
        ),
        GoRoute(
          path: '/appointments',
          builder: (context, state) => const AppointmentsScreen(),
        ),
        GoRoute(
          path: '/vaccinations',
          builder: (context, state) => const VaccinationProtocolsScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/settings/work-hours',
          builder: (context, state) => const ClinicWorkHoursScreen(),
        ),
        GoRoute(
          path: '/inventory',
          builder: (context, state) => const InventoryScreen(),
        ),
        GoRoute(
          path: '/billing',
          builder: (context, state) => const BillingScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.reports,
            child: ReportsScreen(),
          ),
        ),
        GoRoute(
          path: '/backup',
          builder: (context, state) => const BackupScreen(),
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) => AuthenticationScreen(
            clinicName: state.uri.queryParameters['clinicName'],
          ),
        ),
        GoRoute(
          path: '/administration',
          builder: (context, state) => const ClinicAdministrationScreen(),
        ),
        GoRoute(
          path: '/administration/users',
          builder: (context, state) => const ClinicUserManagementScreen(),
        ),
        GoRoute(
          path: '/administration/users/new',
          builder: (context, state) => const AddClinicUserScreen(),
        ),
      ],
    ),
  ],
);
