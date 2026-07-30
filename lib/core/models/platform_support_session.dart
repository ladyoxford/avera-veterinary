class PlatformSupportSession {
  const PlatformSupportSession({
    required this.clinicId,
    required this.clinicName,
    required this.startedAt,
    required this.startedBy,
  });

  final String clinicId;
  final String clinicName;
  final DateTime startedAt;
  final String startedBy;
}
