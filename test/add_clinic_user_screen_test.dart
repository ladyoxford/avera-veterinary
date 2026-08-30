import 'dart:async';

import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/remote/auth_remote_data_source.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/staff/professional_title_catalog.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/administration/screens/administration_screens.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late _InvitationRepository repository;
  late UserSession session;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = _InvitationRepository(database);
    session = await repository.cacheRemoteSession(
      const RemoteCurrentUser(
        userId: 'admin-1',
        clinicId: 'clinic-1',
        accountType: AccountTypes.clinicAdministrator,
        permissions: {Permissions.usersView, Permissions.usersCreate},
        fullName: 'Clinic Administrator',
        email: 'admin@example.test',
        roleId: 'role-admin',
        roleCode: 'clinic_administrator',
        roleName: 'Clinic Administrator',
        clinicName: 'AVERA Clinic',
        clinicStatus: 'Active',
        subscriptionPlan: 'Professional',
      ),
    );
  });

  tearDown(() => database.close());

  test(
    'professional title catalogue covers every assignable standard role',
    () {
      const roles = [
        'veterinarian',
        'veterinary_nurse',
        'receptionist',
        'laboratory_staff',
        'pharmacist',
        'cashier',
        'practice_manager',
        'inventory_officer',
        'sales_representative',
      ];
      expect(professionalTitleCatalogueCovers(roles), isTrue);
      for (final code in roles) {
        final titles = professionalTitlesForRole(
          ClinicRoleOption(id: code, code: code, name: code),
        );
        expect(titles.last, otherProfessionalTitle);
        expect(titles.toSet().length, titles.length);
      }
    },
  );

  testWidgets(
    'production Add User uses shared fields and inline role validation',
    (tester) async {
      await _pumpScreen(tester, repository, session);

      expect(find.byType(AveraLabeledTextField), findsWidgets);
      expect(find.byType(AveraLabeledDropdownField<String>), findsNWidgets(2));
      final titleDropdown = tester.widget<DropdownButtonFormField<String>>(
        find.descendant(
          of: find.byKey(const Key('add-user-professional-title')),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      expect(titleDropdown.onChanged, isNull);
      expect(
        find.textContaining('Invitations are recorded locally for development'),
        findsNothing,
      );

      final submit = find.text('Create Invitation');
      await tester.scrollUntilVisible(
        submit,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(AveraPrimaryActionButton), findsOneWidget);
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Please select a valid staff role.'), findsOneWidget);
      expect(repository.invitationCount, 0);

      final roleField = find.byKey(const Key('add-user-role'));
      await _centerInViewport(tester, roleField);
      await _selectDropdown(tester, roleField, 'role-vet');
      expect(find.text('Please select a valid staff role.'), findsNothing);
      await _selectDropdown(
        tester,
        find.byKey(const Key('add-user-professional-title')),
        'Veterinary Surgeon',
      );
    },
  );

  testWidgets('selected role ID is submitted once and success is explicit', (
    tester,
  ) async {
    await _pumpScreen(tester, repository, session);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Jane Vet');
    await tester.enterText(fields.at(1), 'jane@example.test');
    final roleField = find.byKey(const Key('add-user-role'));
    await _centerInViewport(tester, roleField);
    await _selectDropdown(tester, roleField, 'role-pharmacist');
    await _selectDropdown(
      tester,
      find.byKey(const Key('add-user-professional-title')),
      'Pharmacist',
    );

    final submit = find.text('Create Invitation');
    await tester.scrollUntilVisible(
      submit,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(repository.invitationCount, 1);
    expect(repository.selectedRole?.id, 'role-pharmacist');
    expect(repository.professionalTitle, 'Pharmacist');

    await tester.runAsync(() async {
      repository.completeInvitation();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    for (
      var i = 0;
      i < 10 && find.byType(AlertDialog).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Invitation submitted'), findsOneWidget);
    expect(
      find.textContaining('submitted to the email provider'),
      findsOneWidget,
    );
    expect(find.textContaining('jane@example.test'), findsOneWidget);
  });

  testWidgets(
    'Add User remains scrollable without overflow on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpScreen(tester, repository, session);
      expect(find.byType(ListView), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Create Invitation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing role clears title and Other submits custom title', (
    tester,
  ) async {
    await _pumpScreen(tester, repository, session);
    final roleField = find.byKey(const Key('add-user-role'));
    final titleField = find.byKey(const Key('add-user-professional-title'));
    await tester.enterText(find.byType(TextFormField).at(0), 'Jane Vet');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'jane@example.test',
    );

    await _selectDropdown(tester, roleField, 'role-vet');
    await _selectDropdown(tester, titleField, 'Veterinary Surgeon');
    await _selectDropdown(tester, roleField, 'role-pharmacist');
    final changedTitle = tester.widget<DropdownButtonFormField<String>>(
      find.descendant(
        of: titleField,
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    expect(changedTitle.initialValue, isNull);

    await _selectDropdown(tester, titleField, 'Other');
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(find.text('SPECIFY PROFESSIONAL TITLE'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).last,
      '  Equine Pharmacist  ',
    );
    await tester.scrollUntilVisible(
      find.text('Create Invitation'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Create Invitation'));
    await tester.pump();
    expect(repository.professionalTitle, 'Equine Pharmacist');
  });

  testWidgets('staff number is system assigned and not editable', (
    tester,
  ) async {
    await _pumpScreen(tester, repository, session);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('STAFF NUMBER'), findsOneWidget);
    expect(find.text('Auto-assigned'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Enter staff number'),
      findsNothing,
    );
  });
}

Future<void> _centerInViewport(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pump();
}

Future<void> _selectDropdown(
  WidgetTester tester,
  Finder field,
  String value,
) async {
  final finder = find.descendant(
    of: field,
    matching: find.byType(DropdownButtonFormField<String>),
  );
  final dropdown = tester.widget<DropdownButtonFormField<String>>(finder);
  tester.state<FormFieldState<String>>(finder).didChange(value);
  dropdown.onChanged?.call(value);
  await tester.pump();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ClinicRepository repository,
  UserSession session,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clinicRepositoryProvider.overrideWithValue(repository),
        userSessionProvider.overrideWith((ref) async => session),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const AddClinicUserScreen(backendModeOverride: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _InvitationRepository extends ClinicRepository {
  _InvitationRepository(super.database);

  final Completer<Map<String, dynamic>> _invitation = Completer();
  int invitationCount = 0;
  ClinicRoleOption? selectedRole;
  String? professionalTitle;

  void completeInvitation() {
    if (!_invitation.isCompleted) {
      _invitation.complete({'status': 'Submitted'});
    }
  }

  @override
  Future<List<ClinicRoleOption>> availableClinicRoles(
    UserSession session,
  ) async => const [
    ClinicRoleOption(
      id: 'role-pharmacist',
      code: 'pharmacist',
      name: 'Pharmacist',
    ),
    ClinicRoleOption(
      id: 'role-vet',
      code: 'veterinarian',
      name: 'Veterinarian',
    ),
  ];

  @override
  Future<StaffInvitationResult> inviteClinicUser({
    required UserSession actingSession,
    required String fullName,
    required String email,
    required ClinicRoleOption role,
    String? phoneNumber,
    String? professionalTitle,
    Set<String> permissionOverrides = const {},
  }) async {
    invitationCount += 1;
    selectedRole = role;
    this.professionalTitle = professionalTitle;
    await _invitation.future;
    return const StaffInvitationResult(
      deliveryStatus: 'Submitted',
      staffNumber: '004',
      emailState: 'Submitted',
      provider: 'resend',
      providerMessageId: 'resend-message-1',
    );
  }
}
