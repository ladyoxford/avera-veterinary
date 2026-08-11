import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/cloud_clinical_state.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/remote/remote_clinical_operation_detail.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/screens/clinical_operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _operationId = '2656ae09-8248-4934-a6c6-b7eb3f4e2152';

void main() {
  test('every production operation type has guarded workflow actions', () {
    expect(
      clinicalOperationStatusActions(
        ClinicalOperationModule.surgery,
        'Scheduled',
      ).map((action) => action.status),
      containsAll(['Pre-operative', 'Cancelled']),
    );
    expect(
      clinicalOperationStatusActions(
        ClinicalOperationModule.prescriptions,
        'Draft',
      ).map((action) => action.status),
      containsAll(['Active', 'Cancelled']),
    );
    expect(
      clinicalOperationStatusActions(
        ClinicalOperationModule.imaging,
        'Requested',
      ).map((action) => action.status),
      containsAll(['Scheduled', 'In Progress', 'Cancelled']),
    );
    expect(
      clinicalOperationStatusActions(
        ClinicalOperationModule.documents,
        'Available',
      ).map((action) => action.status),
      containsAll(['Reviewed', 'Archived']),
    );
    expect(
      clinicalOperationStatusActions(
        ClinicalOperationModule.treatmentBoard,
        'Due',
      ).map((action) => action.status),
      containsAll([
        'Administered',
        'Delayed',
        'Withheld',
        'Missed',
        'Cancelled',
      ]),
    );
    expect(
      clinicalOperationStatusActions(
        ClinicalOperationModule.surgery,
        'Completed',
      ),
      isEmpty,
    );
  });

  testWidgets('remote surgery opens a full persisted detail workflow', (
    tester,
  ) async {
    final remote = _FakeClinicalRemoteDataSource(
      module: ClinicalOperationModule.surgery,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicalRemoteDataSourceProvider.overrideWithValue(remote),
          userSessionProvider.overrideWith((ref) async {
            throw StateError('No test session required for read-only detail.');
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RemoteClinicalOperationDetailScreen(
            operationId: _operationId,
            module: ClinicalOperationModule.surgery,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(remote.requestedOperationId, _operationId);
    expect(find.text('Surgery Detail'), findsOneWidget);
    expect(find.text('Caesarian section'), findsOneWidget);
    expect(find.textContaining('BIOCAMP-2026-00003'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Surgical Plan'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Surgical Plan'), findsOneWidget);
    expect(find.text('Pregnancy toxaemia'), findsOneWidget);
    expect(find.text('Dr Anyafugulo'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Open Medical File'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Open Medical File'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final module in ClinicalOperationModule.values) {
    testWidgets(
      '${module.backendType} detail normalizes map-shaped optional JSON',
      (tester) async {
        final remote = _FakeClinicalRemoteDataSource(module: module);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              clinicalRemoteDataSourceProvider.overrideWithValue(remote),
              userSessionProvider.overrideWith((ref) async {
                throw StateError('No test session required for detail.');
              }),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: RemoteClinicalOperationDetailScreen(
                operationId: _operationId,
                module: module,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('${module.title} Detail'), findsOneWidget);
        expect(find.text(_titleFor(module)), findsOneWidget);
        expect(find.textContaining('BIOCAMP-2026-00003'), findsWidgets);
        expect(find.text('Scheduled'), findsWidgets);
        await tester.scrollUntilVisible(
          find.text(_sectionFor(module)),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(_sectionFor(module)), findsOneWidget);
        expect(find.text(_specificValueFor(module)), findsOneWidget);
        expect(
          find.text('Unable to display this clinical record'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('normalizer safely handles null, scalar, list, and map JSON shapes', () {
    final detail = RemoteClinicalOperationDetailPayload.fromJson({
      'operation': {
        'operation_id': _operationId,
        'details': [
          {'indication': 'Clinical indication'},
          'malformed optional value',
        ],
        'items': {
          'first': {'name': 'Medication A'},
          'second': {'name': 'Medication B'},
        },
      },
      'activity': {
        'action': 'clinical_operation.created',
        'previous_summary': 'malformed optional value',
      },
      'allowedNextStatuses': {'Scheduled': true, 'Ignored': false},
    });

    expect(detail.details['indication'], 'Clinical indication');
    expect(detail.items.map((item) => item['name']), [
      'Medication A',
      'Medication B',
    ]);
    expect(detail.activity, hasLength(1));
    expect(detail.allowedNextStatuses, {'Scheduled'});
    expect(normalizedClinicalRecords('invalid optional value'), isEmpty);
    expect(normalizedClinicalDetails(null), isEmpty);
  });
}

class _FakeClinicalRemoteDataSource extends ClinicalRemoteDataSource {
  _FakeClinicalRemoteDataSource({required this.module})
    : super(
        ApiClient(
          baseUrl: 'https://example.test',
          tokens: const TokenStore(FlutterSecureStorage()),
        ),
      );

  final ClinicalOperationModule module;
  String? requestedOperationId;

  @override
  Future<Map<String, dynamic>> clinicalOperation(String operationId) async {
    requestedOperationId = operationId;
    return {
      'operation': {
        'operation_id': _operationId,
        'patient_id': '8d74347e-c75a-46e4-b5aa-26b9ce0f1530',
        'operation_type': module.backendType,
        'title': _titleFor(module),
        'description': 'Prepare the patient for theatre.',
        'assigned_to': 'Dr Anyafugulo',
        'scheduled_at': '2026-08-12T08:30:00.000Z',
        'status': 'Scheduled',
        'priority': 'Urgent',
        'details': _detailsFor(module),
        'items': {
          'name': module == ClinicalOperationModule.treatmentBoard
              ? 'Ceftriaxone'
              : 'Clinical item',
          'dose': {'value': '2 ml'},
        },
        'created_at': '2026-08-10T09:00:00.000Z',
        'updated_at': '2026-08-10T09:00:00.000Z',
        'patient_name': 'Nwanyi Ocha',
        'hospital_number': 'BIOCAMP-2026-00003',
        'owner_name': 'Mama Umuoji',
      },
      'allowedNextStatuses': {'Pre-operative': true, 'Cancelled': true},
      'activity': {
        'action': 'clinical_operation.created',
        'previous_summary': 'malformed optional value',
        'new_summary': {'status': 'Scheduled'},
        'created_at': '2026-08-10T09:00:00.000Z',
      },
    };
  }
}

String _titleFor(ClinicalOperationModule module) => switch (module) {
  ClinicalOperationModule.surgery => 'Caesarian section',
  ClinicalOperationModule.prescriptions => 'Post-operative prescription',
  ClinicalOperationModule.imaging => 'Abdominal imaging request',
  ClinicalOperationModule.documents => 'Discharge document',
  ClinicalOperationModule.treatmentBoard => 'Ward treatment plan',
};

String _sectionFor(ClinicalOperationModule module) => switch (module) {
  ClinicalOperationModule.surgery => 'Surgical Plan',
  ClinicalOperationModule.prescriptions => 'Prescription Details',
  ClinicalOperationModule.imaging => 'Imaging Request',
  ClinicalOperationModule.documents => 'Document Details',
  ClinicalOperationModule.treatmentBoard => 'Treatment Plan',
};

String _specificValueFor(ClinicalOperationModule module) => switch (module) {
  ClinicalOperationModule.surgery => 'Pregnancy toxaemia',
  ClinicalOperationModule.prescriptions => 'Give after meals',
  ClinicalOperationModule.imaging => 'Abdomen',
  ClinicalOperationModule.documents => 'Discharge summary',
  ClinicalOperationModule.treatmentBoard => 'Isolation ward',
};

Map<String, dynamic> _detailsFor(ClinicalOperationModule module) =>
    switch (module) {
      ClinicalOperationModule.surgery => {
        'surgeryType': 'Emergency',
        'indication': 'Pregnancy toxaemia',
        'assistant': {'name': 'Nurse Ada'},
        'anaesthetist': 'Dr Anyafugulo',
      },
      ClinicalOperationModule.prescriptions => {
        'refillAllowance': 0,
        'instructions': 'Give after meals',
      },
      ClinicalOperationModule.imaging => {
        'imagingType': {'value': 'Ultrasound'},
        'anatomicalArea': 'Abdomen',
        'clinicalHistory': ['Reduced appetite', 'Abdominal pain'],
      },
      ClinicalOperationModule.documents => {
        'documentCategory': 'Discharge summary',
        'fileName': {'value': 'discharge.pdf'},
        'sensitiveDocument': false,
      },
      ClinicalOperationModule.treatmentBoard => {
        'orderedBy': {'name': 'Dr Anyafugulo'},
        'ward': 'Isolation ward',
        'instructions': ['Monitor temperature', 'Record appetite'],
      },
    };
