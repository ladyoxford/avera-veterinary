import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/cloud_clinical_state.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/screens/appointments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _appointmentId = '92a4ce80-f37d-4d87-9293-5525fcc46493';
const _patientId = 'cb159739-c0cb-4503-a069-9d64563f47bc';

void main() {
  testWidgets('schedule tap opens the exact production appointment UUID', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: RemoteAppointmentScheduleRow(
              appointment: _appointmentMap,
              session: _session(),
            ),
          ),
        ),
        GoRoute(
          path: '/appointments/:appointmentId',
          builder: (_, state) => Scaffold(
            body: Text('detail:${state.pathParameters['appointmentId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_routerSubject(router));
    await tester.tap(find.text('Bassy'));
    await tester.pumpAndSettle();

    expect(find.text('detail:$_appointmentId'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'schedule long press opens actions without triggering normal tap',
    (tester) async {
      expect(_session().can(Permissions.appointmentsStartConsultation), isTrue);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => Scaffold(
              body: RemoteAppointmentScheduleRow(
                appointment: _appointmentMap,
                session: _session(),
              ),
            ),
          ),
          GoRoute(
            path: '/appointments/:appointmentId',
            builder: (_, state) => const Scaffold(body: Text('DETAIL ROUTE')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_routerSubject(router));
      await tester.longPress(find.text('Bassy'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Start New Consultation'), findsOneWidget);
      expect(find.text('Reschedule'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Cancel Visit'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Completed')).style?.color,
        AppTheme.success,
      );
      expect(
        tester.widget<Text>(find.text('Reschedule')).style?.color,
        AppTheme.warning,
      );
      expect(
        tester.widget<Text>(find.text('Cancel Visit')).style?.color,
        AppTheme.error,
      );
      expect(find.text('DETAIL ROUTE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('appointment detail renders human dates and authorized actions', (
    tester,
  ) async {
    await tester.pumpWidget(_detailSubject());
    await tester.pumpAndSettle();

    expect(find.text('Bassy'), findsOneWidget);
    expect(find.text('BIOCAMP-2026-00002'), findsOneWidget);
    expect(find.text('August 9, 2026'), findsOneWidget);
    expect(find.text('2026-08-09T22:33:48.672Z'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('No reminders enabled.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No reminders enabled.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Start Consultation'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Start Consultation'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Reschedule'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Reschedule'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mark Completed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mark Completed'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Cancel Visit'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cancel Visit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'start consultation carries canonical patient and appointment IDs',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const CloudAppointmentDetailScreen(
              appointmentId: _appointmentId,
            ),
          ),
          GoRoute(
            path: '/consultations/new',
            builder: (_, state) => Scaffold(
              body: Text(
                'consult:${state.uri.queryParameters['patientId']}:${state.uri.queryParameters['appointmentId']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_routerSubject(router, withDetail: true));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Start Consultation'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Start Consultation'));
      await tester.pumpAndSettle();

      expect(find.text('consult:$_patientId:$_appointmentId'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel visit requires deliberate confirmation', (tester) async {
    await tester.pumpWidget(_detailSubject());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cancel Visit'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Cancel Visit'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel Visit?'), findsOneWidget);
    expect(find.text('Keep Appointment'), findsOneWidget);
    expect(
      find.text('Are you sure you want to cancel this appointment?'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _detailSubject() => ProviderScope(
  overrides: _overrides,
  child: MaterialApp(
    theme: AppTheme.dark(),
    home: const CloudAppointmentDetailScreen(appointmentId: _appointmentId),
  ),
);

Widget _routerSubject(GoRouter router, {bool withDetail = false}) =>
    ProviderScope(
      overrides: withDetail ? _overrides : const [],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    );

final _overrides = [
  userSessionProvider.overrideWith((ref) async => _session()),
  remoteAppointmentDetailProvider.overrideWith((ref, appointmentId) async {
    expect(appointmentId, _appointmentId);
    return _detail;
  }),
];

const _appointmentMap = <String, dynamic>{
  'schedule_entry_id': _appointmentId,
  'patient_id': _patientId,
  'patient_name': 'Bassy',
  'visit_type': 'Grooming',
  'scheduled_at': '2026-08-09T22:33:48.672Z',
  'status': 'Confirmed',
};

final _detail = RemoteAppointmentDetail(
  id: _appointmentId,
  patientId: _patientId,
  patient: RemotePatient(
    id: _patientId,
    hospitalNumber: 'BIOCAMP-2026-00002',
    name: 'Bassy',
    species: 'Ferret',
    breed: 'Champagne',
    sex: 'Female',
    status: 'Active',
    ownerName: 'Danny Okafor',
    ownerPhone: '07060000000',
  ),
  scheduledAt: DateTime.parse('2026-08-09T22:33:48.672Z'),
  visitType: 'Grooming',
  status: 'Confirmed',
  revision: 3,
  notes: 'Routine coat care.',
  assignedStaffId: 'a54e8550-f62d-4d7f-9da7-914dc15211a5',
  assignedStaffName: 'Dr Chukwu',
);

UserSession _session() => UserSession(
  user: AppUser(
    userId: 'admin-user',
    clinicId: 'clinic-1',
    fullName: 'Clinic Administrator',
    username: 'admin@avera.test',
    email: 'admin@avera.test',
    passwordHash: 'not-used',
    role: 'Clinic Administrator',
    accountType: AccountTypes.clinicAdministrator,
    permissions: '[]',
    invitationStatus: 'Accepted',
    requiresPasswordChange: false,
    twoFactorEnabled: false,
    accountStatus: 'Active',
    membershipStatus: 'Active',
    rememberMe: false,
    sessionTimeoutMinutes: 30,
    createdAt: DateTime(2026),
  ),
  clinic: Clinic(
    clinicId: 'clinic-1',
    clinicName: 'Biocamp Veterinary Clinic',
    clinicType: 'Veterinary Clinic',
    currency: 'NGN',
    timeZone: 'Africa/Lagos',
    preferredLanguage: 'English',
    themeColor: '#087F7B',
    dateRegistered: DateTime(2026),
    subscriptionPlan: 'Professional',
    clinicStatus: 'Active',
    patientNumberSequenceLength: 5,
    patientNumberResetYearly: true,
    patientNumberPrefixReviewed: true,
  ),
  backendPermissions: const {
    Permissions.appointmentsView,
    Permissions.appointmentsEdit,
    Permissions.appointmentsCancel,
    Permissions.appointmentsStartConsultation,
    Permissions.patientsView,
    Permissions.consultationsCreate,
  },
);
