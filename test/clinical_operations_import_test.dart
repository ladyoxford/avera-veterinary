import 'package:avera/features/shared/screens/clinical_operations_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clinical operation form definitions load', () {
    expect(ClinicalOperationModule.values, hasLength(5));
    expect(
      ClinicalOperationModule.prescriptions.primaryActionLabel,
      'Create Prescription',
    );
    expect(ClinicalOperationModule.surgery.backendType, 'Surgery');
    expect(ClinicalOperationModule.prescriptions.backendType, 'Prescription');
    expect(ClinicalOperationModule.imaging.backendType, 'Imaging');
    expect(ClinicalOperationModule.documents.backendType, 'Document');
    expect(ClinicalOperationModule.treatmentBoard.backendType, 'Treatment');
  });
}
