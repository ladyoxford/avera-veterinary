import '../../../core/repositories/clinic_repository.dart';

String? clinicActivityRoute(ClinicActivityTimelineEvent event) {
  final id = event.relatedEntityId?.trim();
  if (id == null || id.isEmpty) return null;
  final entityType = event.relatedEntityType;
  final isConsultation =
      entityType == 'Consultation' ||
      event.type.toLowerCase().contains('consultation');
  if (isConsultation) {
    final patientId = event.remotePatientId?.trim();
    return patientId == null || patientId.isEmpty
        ? '/consultations/$id'
        : '/consultations/$id?patientId=${Uri.encodeQueryComponent(patientId)}';
  }
  return switch (entityType) {
    'Appointment' || 'Schedule' => '/appointments/$id',
    'Vaccination' => '/vaccinations/$id',
    'Patient' => '/animals/$id',
    'Invoice' => '/billing/history?invoiceId=$id',
    'ClinicalOperation' => switch (event.module) {
      ClinicalOperationTypes.prescription =>
        '/operations/prescriptions?recordId=$id',
      ClinicalOperationTypes.treatment =>
        '/operations/treatment-board?recordId=$id',
      ClinicalOperationTypes.surgery => '/operations/surgery?recordId=$id',
      ClinicalOperationTypes.imaging => '/operations/imaging?recordId=$id',
      ClinicalOperationTypes.document => '/operations/documents?recordId=$id',
      _ => null,
    },
    _ => null,
  };
}

String? remoteDashboardActivityRoute(Map<String, dynamic> entry) {
  final id = (entry['record_id'] ?? entry['related_entity_id'])
      ?.toString()
      .trim();
  if (id == null || id.isEmpty) return null;
  final type = (entry['related_entity_type'] ?? entry['type'])
      ?.toString()
      .trim();
  final patientId = entry['patient_id']?.toString().trim();
  final module = entry['module']?.toString().trim().toLowerCase();
  return switch (type) {
    'Appointment' || 'Schedule' => '/appointments/$id',
    'Consultation' =>
      patientId == null || patientId.isEmpty
          ? '/consultations/$id'
          : '/consultations/$id?patientId=${Uri.encodeQueryComponent(patientId)}',
    'Vaccination' => '/vaccinations/$id',
    'Patient' => '/animals/$id',
    'Invoice' => '/billing/history?invoiceId=$id',
    'ClinicalOperation' => switch (module) {
      ClinicalOperationTypes.prescription =>
        '/operations/prescriptions?recordId=$id',
      ClinicalOperationTypes.treatment =>
        '/operations/treatment-board?recordId=$id',
      ClinicalOperationTypes.surgery => '/operations/surgery?recordId=$id',
      ClinicalOperationTypes.imaging => '/operations/imaging?recordId=$id',
      ClinicalOperationTypes.document => '/operations/documents?recordId=$id',
      _ => null,
    },
    _ => null,
  };
}
