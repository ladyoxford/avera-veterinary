enum AlertDestinationType {
  inventoryFilteredList,
  vaccineScheduleFilteredList,
  vaccinationRecord,
  appointmentDetail,
  patientDetail,
  consultationDetail,
  notificationCenter,
  none,
}

enum InAppNotificationStatus { unread, read, reviewed, dismissed }

extension AlertDestinationTypeStorage on AlertDestinationType {
  String get storageValue => name;

  static AlertDestinationType fromStorage(String? value) =>
      AlertDestinationType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => AlertDestinationType.none,
      );
}

extension InAppNotificationStatusStorage on InAppNotificationStatus {
  String get storageValue => name;

  static InAppNotificationStatus fromStorage(
    String? value, {
    bool isRead = false,
  }) {
    if (value == null || value.isEmpty) {
      return isRead
          ? InAppNotificationStatus.read
          : InAppNotificationStatus.unread;
    }
    return InAppNotificationStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => isRead
          ? InAppNotificationStatus.read
          : InAppNotificationStatus.unread,
    );
  }
}

class AlertDestination {
  const AlertDestination({required this.type, this.entityId, this.clinicId});

  final AlertDestinationType type;
  final int? entityId;
  final String? clinicId;
}
