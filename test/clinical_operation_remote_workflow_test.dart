import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/cloud_clinical_state.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
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
    final remote = _FakeClinicalRemoteDataSource();
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
}

class _FakeClinicalRemoteDataSource extends ClinicalRemoteDataSource {
  _FakeClinicalRemoteDataSource()
    : super(
        ApiClient(
          baseUrl: 'https://example.test',
          tokens: const TokenStore(FlutterSecureStorage()),
        ),
      );

  String? requestedOperationId;

  @override
  Future<Map<String, dynamic>> clinicalOperation(String operationId) async {
    requestedOperationId = operationId;
    return {
      'operation': {
        'operation_id': _operationId,
        'patient_id': '8d74347e-c75a-46e4-b5aa-26b9ce0f1530',
        'operation_type': 'Surgery',
        'title': 'Caesarian section',
        'description': 'Prepare the patient for theatre.',
        'assigned_to': 'Dr Anyafugulo',
        'scheduled_at': '2026-08-12T08:30:00.000Z',
        'status': 'Scheduled',
        'priority': 'Urgent',
        'details': {
          'surgeryType': 'Emergency',
          'indication': 'Pregnancy toxaemia',
          'assistant': 'Nurse Ada',
          'anaesthetist': 'Dr Anyafugulo',
        },
        'items': <Map<String, dynamic>>[],
        'created_at': '2026-08-10T09:00:00.000Z',
        'updated_at': '2026-08-10T09:00:00.000Z',
        'patient_name': 'Nwanyi Ocha',
        'hospital_number': 'BIOCAMP-2026-00003',
        'owner_name': 'Mama Umuoji',
      },
      'allowedNextStatuses': ['Pre-operative', 'Cancelled'],
      'activity': <Map<String, dynamic>>[],
    };
  }
}
