import '../database/app_database.dart';

/// Local numbering is authoritative only for the active Drift database.
/// A future backend allocator can implement the same contract without changing
/// registration widgets or patient relationships.
enum HospitalNumberAuthorityMode { localOnly, remoteAuthoritative }

enum NumberAssignmentStatus {
  legacy('Legacy'),
  assigned('Assigned'),
  temporary('Temporary'),
  pendingAssignment('Pending Assignment'),
  assignmentFailed('Assignment Failed');

  const NumberAssignmentStatus(this.databaseValue);
  final String databaseValue;
}

class HospitalNumberPreview {
  const HospitalNumberPreview({
    required this.clinicId,
    required this.prefix,
    required this.year,
    required this.sequence,
    required this.sequenceLength,
    required this.prefixRequiresReview,
  });

  final String clinicId;
  final String prefix;
  final int year;
  final int sequence;
  final int sequenceLength;
  final bool prefixRequiresReview;

  String get hospitalNumber => formatHospitalNumber(
    prefix: prefix,
    year: year,
    sequence: sequence,
    sequenceLength: sequenceLength,
  );
}

class AssignedHospitalNumber {
  const AssignedHospitalNumber({
    required this.patientId,
    required this.hospitalNumber,
    required this.submissionId,
  });

  final int patientId;
  final String hospitalNumber;
  final String submissionId;
}

abstract interface class AppClock {
  DateTime nowForClinic(Clinic clinic);
}

class LocalAppClock implements AppClock {
  const LocalAppClock();

  @override
  DateTime nowForClinic(Clinic clinic) {
    // Local-first AVERA currently supports the configured Nigerian clinic
    // timezone explicitly. Other zones use the device-local clock until a
    // timezone database is introduced with the remote authority.
    if (clinic.timeZone == 'Africa/Lagos') {
      return DateTime.now().toUtc().add(const Duration(hours: 1));
    }
    return DateTime.now();
  }
}

String? validateHospitalNumberPrefix(String value) {
  final trimmed = value.trim();
  if (!RegExp(r'^[A-Za-z0-9]{2,8}$').hasMatch(trimmed)) {
    return 'Use 2-8 letters or numbers without spaces or symbols.';
  }
  return null;
}

String normalizeHospitalNumberPrefix(String value) {
  final error = validateHospitalNumberPrefix(value);
  if (error != null) throw ArgumentError(error);
  return value.trim().toUpperCase();
}

String formatHospitalNumber({
  required String prefix,
  required int year,
  required int sequence,
  required int sequenceLength,
}) {
  final normalizedPrefix = normalizeHospitalNumberPrefix(prefix);
  if (sequence < 1) throw ArgumentError.value(sequence, 'sequence');
  if (sequenceLength < 4 || sequenceLength > 10) {
    throw ArgumentError.value(sequenceLength, 'sequenceLength');
  }
  return '$normalizedPrefix-$year-${sequence.toString().padLeft(sequenceLength, '0')}';
}

String suggestHospitalNumberPrefix(Clinic clinic) {
  if (clinic.patientNumberPrefix?.trim().isNotEmpty ?? false) {
    return normalizeHospitalNumberPrefix(clinic.patientNumberPrefix!);
  }
  if (clinic.clinicId == defaultClinicId ||
      clinic.clinicName.toLowerCase() == 'avera veterinary clinic') {
    return 'AVR';
  }
  const ignored = {
    'veterinary',
    'vet',
    'clinic',
    'hospital',
    'animal',
    'pet',
    'care',
    'services',
  };
  final words = clinic.clinicName
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((word) => word.isNotEmpty && !ignored.contains(word.toLowerCase()))
      .toList();
  final initials = words.map((word) => word[0]).join();
  final compact = words.join();
  final candidate = initials.length >= 2
      ? initials
      : compact.length >= 2
      ? compact.substring(0, compact.length > 8 ? 8 : compact.length)
      : 'AVR';
  return normalizeHospitalNumberPrefix(candidate);
}
