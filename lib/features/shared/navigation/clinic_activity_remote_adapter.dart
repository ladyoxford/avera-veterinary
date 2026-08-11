import '../../../core/repositories/clinic_repository.dart';

ClinicActivityTimelineEvent clinicActivityEventFromRemote(
  Map<String, dynamic> value, {
  required String clinicId,
  required int index,
}) {
  final type = _text(value['type']) ?? 'ClinicActivity';
  final title =
      _text(value['title']) ?? _text(value['summary']) ?? 'Clinic activity';
  final description = _text(value['summary']) ?? type;
  final occurredAt =
      DateTime.tryParse('${value['occurred_at']}') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final relatedEntityId = _text(
    value['record_id'] ?? value['related_entity_id'],
  );
  final relatedEntityType =
      _text(value['related_entity_type']) ??
      (relatedEntityId == null ? null : type);
  final rawModule = _text(value['module']);
  final module = relatedEntityType == 'ClinicalOperation'
      ? rawModule?.toLowerCase()
      : rawModule;

  return ClinicActivityTimelineEvent(
    id:
        _text(value['id']) ??
        '${occurredAt.microsecondsSinceEpoch}-$index-${relatedEntityId ?? type}',
    clinicId: clinicId,
    type: type,
    title: title,
    description: description,
    occurredAt: occurredAt.toLocal(),
    performedByUserId: _text(value['performed_by_user_id']),
    relatedEntityType: relatedEntityType,
    relatedEntityId: relatedEntityId,
    remotePatientId: _text(value['patient_id']),
    module: module,
  );
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
