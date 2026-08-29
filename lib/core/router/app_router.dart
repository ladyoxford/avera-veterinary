import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/animals/screens/animal_registration_screen.dart';
import '../../features/animals/screens/animal_search_screen.dart';
import '../../features/animals/screens/archived_animals_screen.dart';
import '../../features/animals/screens/medical_file_hub_screen.dart';
import '../database/app_database.dart';
import '../models/inventory_catalog.dart';
import '../models/vaccine_catalogue.dart';
import '../remote/api_client.dart';
import '../../features/authentication/screens/authentication_screen.dart';
import '../../features/authentication/screens/clinic_registration_screen.dart';
import '../../features/authentication/screens/clinic_registration_payment_screen.dart';
import '../../features/authentication/screens/clinic_administrator_activation_screen.dart';
import 'activation_link.dart';
import '../../features/authentication/screens/password_reset_screens.dart';
import '../../features/authentication/screens/offline_access_screens.dart';
import '../../features/authentication/screens/security_auth_screens.dart';
import '../../features/administration/screens/administration_screens.dart';
import '../../features/administration/screens/clinic_administration_modules.dart';
import '../../features/administration/screens/staff_management_screen.dart';
import '../../features/administration/screens/platform_management_screens.dart';
import '../../features/administration/screens/functional_platform_dashboard.dart';
import '../../features/administration/widgets/platform_owner_shell.dart';
import '../../features/administration/screens/subscription_plans_screen.dart';
import '../../features/administration/screens/clinic_work_hours_screen.dart';
import '../../features/administration/screens/patient_numbering_screen.dart';
import '../../features/billing/screens/billing_screen.dart';
import '../../features/billing/screens/billing_history_screen.dart';
import '../../features/billing/screens/revenue_profit_screen.dart';
import '../../features/consultation/screens/consultation_screen.dart';
import '../../features/consultation/screens/cloud_consultation_detail_screen.dart';
import '../../features/consultation/screens/cloud_consultation_edit_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/farm/widgets/farm_back_navigation.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/shared/screens/appointments_screen.dart';
import '../../features/shared/screens/backup_screen.dart';
import '../../features/shared/screens/clinic_operations_screens.dart';
import '../../features/shared/screens/clinical_operations_screen.dart';
import '../../features/shared/screens/dashboard_screen.dart';
import '../../features/shared/screens/activity_history_screen.dart';
import '../../features/shared/screens/notifications_screen.dart';
import '../../features/shared/screens/settings_screen.dart';
import '../../features/shared/screens/my_profile_screen.dart';
import '../../features/shared/screens/splash_screen.dart';
import '../../features/farm/screens/farm_records_screen.dart';
import '../../features/farm/screens/farm_profile_editor_screen.dart';
import '../../features/farm/screens/farm_detail_screens.dart';
import '../../features/farm/screens/farm_daily_record_editor_screen.dart';
import '../../features/shared/widgets/app_scaffold.dart';
import '../../features/shared/widgets/feature_gate.dart';
import '../../features/vaccination/screens/vaccination_screen.dart';
import '../../features/vaccination/screens/cloud_vaccination_detail_screen.dart';
import '../../features/vera/screens/vera_screen.dart';
import '../services/feature_gate_service.dart';

Widget _clinicalOperationDestination(
  GoRouterState state,
  ClinicalOperationModule module,
) {
  final recordId = state.uri.queryParameters['recordId']?.trim();
  final openDetailDirectly =
      BackendConfiguration.isConfigured &&
      state.uri.queryParameters['direct'] == 'true' &&
      recordId != null &&
      recordId.isNotEmpty;
  if (openDetailDirectly) {
    return RemoteClinicalOperationDetailScreen(
      operationId: recordId,
      module: module,
    );
  }
  return ClinicalOperationScreen(
    module: module,
    initialRecordId: int.tryParse(recordId ?? ''),
    initialRemoteRecordId: recordId,
  );
}

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (context, state) => const AuthenticationScreen(),
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
      path: '/payments/registration-callback',
      builder: (context, state) => ClinicRegistrationPaymentCallbackScreen(
        reference: state.uri.queryParameters['reference'],
      ),
    ),
    GoRoute(
      path: '/activate-clinic-admin',
      builder: (context, state) => ClinicAdministratorActivationScreen(
        token: clinicAdministratorActivationToken(state.uri) ?? '',
      ),
    ),
    GoRoute(
      path: '/activate-staff',
      builder: (context, state) => ClinicAdministratorActivationScreen(
        token: staffActivationToken(state.uri) ?? '',
        staffActivation: true,
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
      path: '/mfa-challenge',
      builder: (context, state) =>
          MfaChallengeScreen(args: state.extra! as MfaChallengeArgs),
    ),
    GoRoute(
      path: '/account-restricted',
      builder: (context, state) => const AccountAccessRestrictedScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => PlatformOwnerShell(child: child),
      routes: [
        GoRoute(
          path: '/platform',
          builder: (context, state) =>
              const FunctionalPlatformOwnerDashboardScreen(),
        ),
        GoRoute(
          path: '/platform/clinics',
          builder: (context, state) => PlatformClinicsScreen(
            status: state.uri.queryParameters['status'],
          ),
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
            message:
                'Global settings are ready for secure backend configuration.',
            icon: Icons.settings_outlined,
          ),
        ),
        GoRoute(
          path: '/platform/operations',
          builder: (context, state) => const PlatformOperationsScreen(),
        ),
        GoRoute(
          path: '/platform/account',
          builder: (context, state) => const PlatformAccountScreen(),
        ),
        GoRoute(
          path: '/platform/developer-settings',
          builder: (context, state) => const PlatformDeveloperSettingsScreen(),
        ),
        GoRoute(
          path: '/platform/password',
          builder: (context, state) => const PlatformPasswordScreen(),
        ),
      ],
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
        GoRoute(
          path: '/payments/callback',
          builder: (context, state) => SubscriptionPaymentCallbackScreen(
            reference: state.uri.queryParameters['reference'],
          ),
        ),
        GoRoute(path: '/more', builder: (context, state) => const MoreScreen()),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const MyProfileScreen(),
        ),
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
          builder: (context, state) => const VaccineScheduleScreen(),
        ),
        GoRoute(
          path: '/operations/laboratory',
          builder: (context, state) => FeatureGate(
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
          builder: (context, state) => FeatureGate(
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
          builder: (context, state) => FeatureGate(
            feature: AveraFeature.treatmentBoard,
            child: _clinicalOperationDestination(
              state,
              ClinicalOperationModule.treatmentBoard,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/surgery',
          builder: (context, state) => FeatureGate(
            feature: AveraFeature.surgery,
            child: _clinicalOperationDestination(
              state,
              ClinicalOperationModule.surgery,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/prescriptions',
          builder: (context, state) => FeatureGate(
            feature: AveraFeature.prescriptions,
            child: _clinicalOperationDestination(
              state,
              ClinicalOperationModule.prescriptions,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/imaging',
          builder: (context, state) => FeatureGate(
            feature: AveraFeature.imaging,
            child: _clinicalOperationDestination(
              state,
              ClinicalOperationModule.imaging,
            ),
          ),
        ),
        GoRoute(
          path: '/operations/documents',
          builder: (context, state) => FeatureGate(
            feature: AveraFeature.documents,
            child: _clinicalOperationDestination(
              state,
              ClinicalOperationModule.documents,
            ),
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
          builder: (context, state) => AnimalRegistrationScreen(
            returnResult: state.uri.queryParameters['returnResult'] == 'true',
          ),
        ),
        GoRoute(
          path: '/animals/:id',
          builder: (context, state) => BackendConfiguration.isConfigured
              ? CloudMedicalFileHubScreen(
                  patientId: state.pathParameters['id']!,
                )
              : MedicalFileHubScreen(
                  animalId: int.parse(state.pathParameters['id']!),
                ),
        ),
        GoRoute(
          path: '/consultations/new',
          builder: (context, state) => ConsultationScreen(
            initialRemotePatientId: BackendConfiguration.isConfigured
                ? state.uri.queryParameters['patientId'] ??
                      state.uri.queryParameters['animalId']
                : null,
            initialAnimalId: int.tryParse(
              state.uri.queryParameters['animalId'] ?? '',
            ),
            initialAppointmentId: int.tryParse(
              state.uri.queryParameters['appointmentId'] ?? '',
            ),
            initialComplaint: state.uri.queryParameters['complaint'],
            initialVeterinarian: state.uri.queryParameters['veterinarian'],
          ),
        ),
        GoRoute(
          path: '/consultations/:consultationId/edit',
          builder: (context, state) => BackendConfiguration.isConfigured
              ? CloudConsultationEditScreen(
                  consultationId: state.pathParameters['consultationId']!,
                  patientId: state.uri.queryParameters['patientId'] ?? '',
                )
              : ConsultationScreen(
                  mode: ConsultationScreenMode.edit,
                  consultationId: int.parse(
                    state.pathParameters['consultationId']!,
                  ),
                ),
        ),
        GoRoute(
          path: '/consultations/:consultationId',
          builder: (context, state) => BackendConfiguration.isConfigured
              ? CloudConsultationDetailScreen(
                  consultationId: state.pathParameters['consultationId']!,
                  patientId: state.uri.queryParameters['patientId'] ?? '',
                )
              : ConsultationScreen(
                  mode: ConsultationScreenMode.view,
                  consultationId: int.parse(
                    state.pathParameters['consultationId']!,
                  ),
                ),
        ),
        GoRoute(
          path: '/appointments',
          builder: (context, state) => const AppointmentsScreen(),
        ),
        GoRoute(
          path: '/activity-history',
          builder: (context, state) => const ActivityHistoryScreen(),
        ),
        GoRoute(
          path: '/appointments/new',
          builder: (context, state) => const NewAppointmentScreen(),
        ),
        GoRoute(
          path: '/appointments/:appointmentId',
          builder: (context, state) => BackendConfiguration.isConfigured
              ? CloudAppointmentDetailScreen(
                  appointmentId: state.pathParameters['appointmentId']!,
                )
              : AppointmentDetailScreen(
                  appointmentId: int.parse(
                    state.pathParameters['appointmentId']!,
                  ),
                ),
        ),
        GoRoute(
          path: '/vaccinations',
          builder: (context, state) => VaccineScheduleScreen(
            initialFilter: switch (state.uri.queryParameters['filter']) {
              'due-now' => VaccineScheduleFilter.dueNow,
              'due-today' => VaccineScheduleFilter.dueToday,
              'overdue' => VaccineScheduleFilter.overdue,
              'upcoming' => VaccineScheduleFilter.upcoming,
              _ => VaccineScheduleFilter.all,
            },
          ),
        ),
        GoRoute(
          path: '/vaccinations/record',
          builder: (context, state) {
            final remotePatientId =
                state.uri.queryParameters['remotePatientId'];
            final remoteVaccinationId =
                state.uri.queryParameters['remoteVaccinationId'];
            final remoteVaccineName = state.uri.queryParameters['vaccineName'];
            final patientId = int.tryParse(
              state.uri.queryParameters['patientId'] ?? '',
            );
            final scheduleId = int.tryParse(
              state.uri.queryParameters['scheduleId'] ?? '',
            );
            final protocolId = state.uri.queryParameters['protocolId'];
            final args =
                remotePatientId != null &&
                    remoteVaccinationId != null &&
                    remoteVaccineName != null
                ? RecordVaccinationArgs.remoteScheduledDose(
                    remotePatientId: remotePatientId,
                    remoteVaccinationId: remoteVaccinationId,
                    remoteVaccineName: remoteVaccineName,
                  )
                : patientId != null && scheduleId != null && protocolId != null
                ? RecordVaccinationArgs.scheduledDose(
                    patientId: patientId,
                    vaccinationScheduleId: scheduleId,
                    vaccineProtocolId: protocolId,
                  )
                : const RecordVaccinationArgs.general();
            return RecordVaccinationScreen(args: args);
          },
        ),
        GoRoute(
          path: '/vaccinations/:vaccinationId',
          builder: (context, state) => BackendConfiguration.isConfigured
              ? CloudVaccinationDetailScreen(
                  vaccinationId: state.pathParameters['vaccinationId']!,
                )
              : VaccinationDetailScreen(
                  vaccinationId: int.parse(
                    state.pathParameters['vaccinationId']!,
                  ),
                ),
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
          path: '/settings/clinic-information',
          builder: (context, state) => const ClinicInformationScreen(),
        ),
        GoRoute(
          path: '/settings/about',
          builder: (context, state) => const AboutAveraScreen(),
        ),
        GoRoute(
          path: '/settings/support',
          builder: (context, state) => const SupportScreen(),
        ),
        GoRoute(
          path: '/settings/privacy',
          builder: (context, state) => const PrivacyPolicyScreen(),
        ),
        GoRoute(
          path: '/settings/work-hours',
          builder: (context, state) => const ClinicWorkHoursScreen(),
        ),
        GoRoute(
          path: '/settings/patient-numbering',
          builder: (context, state) => const PatientNumberingScreen(),
        ),
        GoRoute(
          path: '/inventory',
          builder: (context, state) => InventoryScreen(
            initialStatusFilter: switch (state.uri.queryParameters['filter']) {
              'low' => InventoryStatusFilter.lowStock,
              'expired' => InventoryStatusFilter.expired,
              _ => InventoryStatusFilter.all,
            },
          ),
        ),
        GoRoute(
          path: '/billing',
          builder: (context, state) =>
              BillingScreen(initialFarmId: state.uri.queryParameters['farmId']),
        ),
        GoRoute(
          path: '/billing/history',
          builder: (context, state) => BillingHistoryScreen(
            initialInvoiceId: state.uri.queryParameters['invoiceId'],
            initialContext: state.uri.queryParameters['context'],
            initialFarmId: state.uri.queryParameters['farmId'],
          ),
        ),
        GoRoute(
          path: '/revenue',
          builder: (context, state) => const RevenueProfitScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const FeatureGate(
            feature: AveraFeature.reports,
            child: ReportsScreen(),
          ),
        ),
        GoRoute(
          path: '/reports/:reportType',
          builder: (context, state) {
            final type = ClinicReportType.fromRoute(
              state.pathParameters['reportType'],
            );
            return FeatureGate(
              feature: AveraFeature.reports,
              child: type == null
                  ? const ReportsScreen()
                  : ReportDetailScreen(type: type),
            );
          },
        ),
        GoRoute(
          path: '/backup',
          builder: (context, state) => const BackupScreen(),
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) => const AuthenticationScreen(),
        ),
        GoRoute(
          path: '/administration',
          builder: (context, state) => const ClinicAdministrationScreen(),
        ),
        GoRoute(
          path: '/administration/users',
          builder: (context, state) => const StaffManagementScreen(),
        ),
        GoRoute(
          path: '/administration/users/new',
          builder: (context, state) => const AddClinicUserScreen(),
        ),
        GoRoute(
          path: '/administration/roles',
          builder: (context, state) => const ClinicRolesPermissionsScreen(),
        ),
        GoRoute(
          path: '/administration/roles/:roleName',
          builder: (context, state) => ClinicRoleDetailsScreen(
            roleName: Uri.decodeComponent(state.pathParameters['roleName']!),
          ),
        ),
        GoRoute(
          path: '/administration/audit',
          builder: (context, state) => ClinicAuditLogsScreen(
            initialCategory: state.uri.queryParameters['category'] == 'security'
                ? ClinicAuditCategory.security
                : ClinicAuditCategory.all,
          ),
        ),
        GoRoute(
          path: '/administration/audit/:auditId',
          builder: (context, state) =>
              AuditEventDetailsScreen(log: state.extra! as AuditLog),
        ),
        GoRoute(
          path: '/administration/security',
          builder: (context, state) => const ClinicSecurityScreen(),
        ),
        GoRoute(
          path: '/administration/security/2fa',
          builder: (context, state) => const TwoFactorAuthenticationScreen(),
        ),
      ],
    ),
    // Farm workflows own their full screen. Keeping them outside AppScaffold
    // prevents clinic navigation from obscuring unit records and modal sheets.
    GoRoute(
      path: '/farm-records',
      builder: (context, state) => const FarmBackNavigationScope(
        fallbackPath: '/more',
        child: FarmRecordsScreen(),
      ),
    ),
    GoRoute(
      path: '/farm-records/new',
      builder: (context, state) => const FarmBackNavigationScope(
        fallbackPath: '/farm-records',
        child: FarmProfileEditorScreen(),
      ),
    ),
    GoRoute(
      path: '/farm-records/:farmId/edit',
      builder: (context, state) => FarmBackNavigationScope(
        fallbackPath: '/farm-records/${state.pathParameters['farmId']!}',
        child: FarmProfileEditorScreen(farmId: state.pathParameters['farmId']!),
      ),
    ),
    GoRoute(
      path: '/farm-records/:farmId/overview',
      builder: (context, state) => FarmBackNavigationScope(
        fallbackPath: '/farm-records/${state.pathParameters['farmId']!}',
        child: FarmOverviewScreen(farmId: state.pathParameters['farmId']!),
      ),
    ),
    GoRoute(
      path: '/farm-records/:farmId/invoice',
      redirect: (context, state) =>
          '/billing?farmId=${state.pathParameters['farmId']!}',
    ),
    GoRoute(
      path: '/farm-records/:farmId/units/:unitId',
      builder: (context, state) => FarmBackNavigationScope(
        fallbackPath: '/farm-records/${state.pathParameters['farmId']!}',
        child: FarmUnitDetailScreen(
          farmId: state.pathParameters['farmId']!,
          unitId: int.parse(state.pathParameters['unitId']!),
        ),
      ),
    ),
    GoRoute(
      path: '/farm-records/:farmId/daily/:recordId',
      builder: (context, state) => FarmBackNavigationScope(
        fallbackPath: '/farm-records/${state.pathParameters['farmId']!}',
        child: FarmDailyRecordDetailScreen(
          farmId: state.pathParameters['farmId']!,
          recordId: state.pathParameters['recordId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/farm-records/:farmId',
      builder: (context, state) => FarmBackNavigationScope(
        fallbackPath: '/farm-records',
        child: FarmDetailScreen(farmId: state.pathParameters['farmId']!),
      ),
    ),
    GoRoute(
      path: '/farm-records/:farmId/daily',
      builder: (context, state) => FarmBackNavigationScope(
        fallbackPath: '/farm-records/${state.pathParameters['farmId']!}',
        child: FarmDailyRecordEditorScreen(
          farmId: state.pathParameters['farmId']!,
          recordId: state.uri.queryParameters['recordId'],
          correctionMode: state.uri.queryParameters['correct'] == 'true',
        ),
      ),
    ),
  ],
);
