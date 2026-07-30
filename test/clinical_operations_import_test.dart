import 'package:avera/features/shared/screens/clinical_operations_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clinical operation form definitions load', () {
    expect(ClinicalOperationModule.values, hasLength(5));
    expect(
      ClinicalOperationModule.prescriptions.primaryActionLabel,
      'Create Prescription',
    );
  });
}
