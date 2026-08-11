class RemoteClinicalOperationDetailPayload {
  const RemoteClinicalOperationDetailPayload({
    required this.operation,
    required this.details,
    required this.items,
    required this.activity,
    required this.allowedNextStatuses,
  });

  final Map<String, dynamic> operation;
  final Map<String, dynamic> details;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> activity;
  final Set<String> allowedNextStatuses;

  factory RemoteClinicalOperationDetailPayload.fromJson(
    Map<String, dynamic> payload,
  ) {
    final operation = normalizedClinicalMap(payload['operation']);
    if (operation.isEmpty) {
      throw const FormatException('Clinical operation payload is missing.');
    }

    final details = normalizedClinicalDetails(operation['details']);
    final items = normalizedClinicalRecords(operation['items']);
    final Set<String> allowedNextStatuses = normalizedClinicalStrings(
      payload['allowedNextStatuses'],
    );
    operation['details'] = details;
    operation['items'] = items;

    return RemoteClinicalOperationDetailPayload(
      operation: operation,
      details: details,
      items: items,
      activity: normalizedClinicalRecords(payload['activity']),
      allowedNextStatuses: allowedNextStatuses,
    );
  }
}

Map<String, dynamic> normalizedClinicalMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, dynamic> normalizedClinicalDetails(Object? value) {
  if (value is Map) return normalizedClinicalMap(value);
  if (value is List) {
    final merged = <String, dynamic>{};
    for (final entry in value) {
      merged.addAll(normalizedClinicalMap(entry));
    }
    return merged;
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> normalizedClinicalRecords(Object? value) {
  if (value is List) {
    return value
        .map(normalizedClinicalMap)
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }
  if (value is Map) {
    final map = normalizedClinicalMap(value);
    final nestedItems = map['items'];
    if (map.length == 1 && nestedItems != null) {
      return normalizedClinicalRecords(nestedItems);
    }
    if (map.isNotEmpty && map.values.every((entry) => entry is Map)) {
      return map.values
          .map(normalizedClinicalMap)
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return map.isEmpty ? const [] : [map];
  }
  return const [];
}

Set<String> normalizedClinicalStrings(Object? value) {
  final values = <String>{};
  if (value is List) {
    values.addAll(value.map((entry) => entry.toString()));
  } else if (value is Map) {
    for (final entry in value.entries) {
      if (entry.value == true) {
        values.add(entry.key.toString());
      } else if (entry.value is String) {
        values.add(entry.value.toString());
      }
    }
  } else if (value is String) {
    values.add(value);
  }
  return <String>{
    for (final entry in values)
      if (entry.trim().isNotEmpty) entry.trim(),
  };
}

String clinicalDisplayValue(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? fallback : text;
  }
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    final text = value
        .map((entry) => clinicalDisplayValue(entry))
        .where((entry) => entry.isNotEmpty)
        .join(', ');
    return text.isEmpty ? fallback : text;
  }
  if (value is Map) {
    final map = normalizedClinicalMap(value);
    if (map.length == 1) {
      return clinicalDisplayValue(map.values.first, fallback: fallback);
    }
    final text = map.entries
        .map((entry) {
          final display = clinicalDisplayValue(entry.value);
          return display.isEmpty ? '' : '${_humanizeKey(entry.key)}: $display';
        })
        .where((entry) => entry.isNotEmpty)
        .join('; ');
    return text.isEmpty ? fallback : text;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String _humanizeKey(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    )
    .replaceAll('_', ' ');
