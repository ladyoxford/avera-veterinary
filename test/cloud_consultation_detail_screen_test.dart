import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/remote/cloud_clinical_state.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/consultation/screens/cloud_consultation_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _patientId = '6a5f8a0b-0b69-41ba-b24f-9ae5ced997b8';
const _consultationId = '3f4cd168-ff17-4be6-8fb2-c73e791c2bcc';

void main() {
  testWidgets('production consultation opens as a read-only medical record', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(_patientId));
    await tester.pumpAndSettle();

    expect(find.text('Luna'), findsWidgets);
    expect(find.textContaining('AVR-2026-00001'), findsOneWidget);
    expect(find.text('Enteritis'), findsOneWidget);
    expect(find.text('Emesis'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dr Ada'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Dr Ada'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<Object>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mismatched patient UUID is rejected safely', (tester) async {
    await tester.pumpWidget(_subject('different-patient'));
    await tester.pumpAndSettle();

    expect(
      find.text('This consultation does not belong to this patient.'),
      findsOneWidget,
    );
    expect(find.text('Enteritis'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _subject(String patientId) => ProviderScope(
  overrides: [
    clinicalRemoteDataSourceProvider.overrideWithValue(
      _FakeClinicalRemoteDataSource(),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.dark(),
    home: CloudConsultationDetailScreen(
      consultationId: _consultationId,
      patientId: patientId,
    ),
  ),
);

class _FakeClinicalRemoteDataSource extends ClinicalRemoteDataSource {
  _FakeClinicalRemoteDataSource()
    : super(
        ApiClient(
          baseUrl: 'https://example.test',
          tokens: const TokenStore(FlutterSecureStorage()),
        ),
      );

  @override
  Future<Map<String, dynamic>> consultation(String consultationId) async {
    expect(consultationId, _consultationId);
    return {
      'consultation_id': _consultationId,
      'patient_id': _patientId,
      'patient_name': 'Luna',
      'hospital_number': 'AVR-2026-00001',
      'occurred_at': '2026-08-06T09:30:00.000Z',
      'chief_complaint': 'Emesis',
      'history': 'Started yesterday',
      'examination': 'Mild dehydration',
      'final_diagnosis': 'Enteritis',
      'treatment': 'Supportive care',
      'prescription_notes': 'Oral rehydration',
      'clinician_name_snapshot': 'Dr Ada',
      'status': 'Completed',
    };
  }
}
