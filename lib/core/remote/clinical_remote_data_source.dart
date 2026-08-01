import 'dart:convert';

import 'api_client.dart';

class RemotePage<T> {
  const RemotePage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.hasNextPage,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasNextPage;
}

class RemotePatient {
  const RemotePatient({
    required this.id,
    required this.hospitalNumber,
    required this.name,
    required this.species,
    required this.status,
    required this.ownerName,
    required this.ownerPhone,
    this.breed,
    this.sex,
    this.imagePlaceholder,
    this.registeredAt,
    this.revision,
  });

  final String id;
  final String hospitalNumber;
  final String name;
  final String species;
  final String status;
  final String ownerName;
  final String ownerPhone;
  final String? breed;
  final String? sex;
  final String? imagePlaceholder;
  final DateTime? registeredAt;
  final int? revision;

  factory RemotePatient.fromJson(Map<String, dynamic> value) => RemotePatient(
    id: value['patient_id'] as String,
    hospitalNumber: value['hospital_number'] as String? ?? '',
    name: value['name'] as String? ?? 'Unnamed patient',
    species: value['species'] as String? ?? 'Unknown',
    status: value['status'] as String? ?? 'Active',
    ownerName: value['owner_name'] as String? ?? 'Unknown owner',
    ownerPhone: value['owner_phone'] as String? ?? '',
    breed: value['breed'] as String?,
    sex: value['sex'] as String?,
    imagePlaceholder: value['image_placeholder'] as String?,
    registeredAt: _date(value['registered_at']),
    revision: value['revision'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'patient_id': id,
    'hospital_number': hospitalNumber,
    'name': name,
    'species': species,
    'status': status,
    'owner_name': ownerName,
    'owner_phone': ownerPhone,
    'breed': breed,
    'sex': sex,
    'image_placeholder': imagePlaceholder,
    'registered_at': registeredAt?.toIso8601String(),
    'revision': revision,
  };
}

class RemoteDashboardSummary {
  const RemoteDashboardSummary({
    required this.registeredPatients,
    required this.todaysSchedule,
    required this.activeConsultations,
    required this.vaccinationsDue,
    required this.lowStock,
    required this.expiredProducts,
    required this.activeHospitalizations,
    required this.pendingLaboratoryReports,
    required this.outstandingInvoices,
    required this.currentRevenue,
    required this.recentActivity,
  });

  final int registeredPatients;
  final int todaysSchedule;
  final int activeConsultations;
  final int vaccinationsDue;
  final int lowStock;
  final int expiredProducts;
  final int activeHospitalizations;
  final int pendingLaboratoryReports;
  final num outstandingInvoices;
  final num currentRevenue;
  final List<Map<String, dynamic>> recentActivity;

  factory RemoteDashboardSummary.fromJson(Map<String, dynamic> value) =>
      RemoteDashboardSummary(
        registeredPatients: _int(value['registered_patients']),
        todaysSchedule: _int(value['todays_schedule']),
        activeConsultations: _int(value['active_consultations']),
        vaccinationsDue: _int(value['vaccinations_due']),
        lowStock: _int(value['low_stock']),
        expiredProducts: _int(value['expired_products']),
        activeHospitalizations: _int(value['active_hospitalizations']),
        pendingLaboratoryReports: _int(value['pending_laboratory_reports']),
        outstandingInvoices: _num(value['outstanding_invoices']),
        currentRevenue: _num(value['current_revenue']),
        recentActivity: (value['recentActivity'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'registered_patients': registeredPatients,
    'todays_schedule': todaysSchedule,
    'active_consultations': activeConsultations,
    'vaccinations_due': vaccinationsDue,
    'low_stock': lowStock,
    'expired_products': expiredProducts,
    'active_hospitalizations': activeHospitalizations,
    'pending_laboratory_reports': pendingLaboratoryReports,
    'outstanding_invoices': outstandingInvoices,
    'current_revenue': currentRevenue,
    'recentActivity': recentActivity,
  };
}

class RemotePatientMedicalFile {
  const RemotePatientMedicalFile({
    required this.patient,
    required this.summaries,
    required this.timeline,
  });
  final RemotePatient patient;
  final Map<String, Map<String, dynamic>> summaries;
  final List<Map<String, dynamic>> timeline;
}

class RemoteHospitalNumberPreview {
  const RemoteHospitalNumberPreview({
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

  factory RemoteHospitalNumberPreview.fromJson(Map<String, dynamic> value) =>
      RemoteHospitalNumberPreview(
        clinicId: value['clinicId'] as String,
        prefix: value['prefix'] as String,
        year: _int(value['year']),
        sequence: _int(value['sequence']),
        sequenceLength: _int(value['sequenceLength']),
        prefixRequiresReview: value['prefixRequiresReview'] == true,
      );
}

class RemotePatientRegistration {
  const RemotePatientRegistration({
    required this.patient,
    required this.submissionId,
    required this.duplicateSubmission,
  });

  final RemotePatient patient;
  final String submissionId;
  final bool duplicateSubmission;

  factory RemotePatientRegistration.fromJson(Map<String, dynamic> value) =>
      RemotePatientRegistration(
        patient: RemotePatient.fromJson(
          Map<String, dynamic>.from(value['patient'] as Map),
        ),
        submissionId: value['submissionId'] as String,
        duplicateSubmission: value['duplicateSubmission'] == true,
      );
}

class ClinicalRemoteDataSource {
  ClinicalRemoteDataSource(this._client);
  final ApiClient _client;

  Future<RemotePage<RemotePatient>> patients({
    int page = 1,
    int pageSize = 25,
    String? search,
    String? status,
  }) async {
    final response = await _client.get(
      _path('/api/v1/patients', {
        'page': '$page',
        'pageSize': '$pageSize',
        if (search?.isNotEmpty ?? false) 'search': search!,
        if (status?.isNotEmpty ?? false) 'status': status!,
      }),
    );
    return _page(response, RemotePatient.fromJson);
  }

  Future<RemoteHospitalNumberPreview> patientNumberPreview() async =>
      RemoteHospitalNumberPreview.fromJson(
        await _client.get('/api/v1/patients/number-preview'),
      );

  Future<RemotePatientRegistration> registerPatient(
    Map<String, dynamic> payload,
  ) async => RemotePatientRegistration.fromJson(
    await _client.post('/api/v1/patients', body: payload, authenticated: true),
  );

  Future<RemotePatientMedicalFile> medicalFile(String patientId) async {
    final value = await _client.get('/api/v1/patients/$patientId/medical-file');
    final summaries = Map<String, dynamic>.from(value['summaries'] as Map);
    return RemotePatientMedicalFile(
      patient: RemotePatient.fromJson(
        Map<String, dynamic>.from(value['patient'] as Map),
      ),
      summaries: summaries.map(
        (key, item) => MapEntry(key, Map<String, dynamic>.from(item as Map)),
      ),
      timeline: (value['timeline'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }

  Future<RemotePage<Map<String, dynamic>>> patientSection(
    String patientId,
    String section, {
    int page = 1,
  }) async {
    final response = await _client.get(
      _path('/api/v1/patients/$patientId/$section', {
        'page': '$page',
        'pageSize': '25',
      }),
    );
    return _page(response, (value) => value);
  }

  /// Typed entry points for the clinic-wide lists. Their item payloads remain
  /// maps until each existing module is migrated from its local Drift model.
  Future<RemotePage<Map<String, dynamic>>> owners({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/owners', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> consultations({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/consultations', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> vaccinations({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/vaccinations', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> laboratory({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/laboratory-reports', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> hospitalizations({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/hospitalizations', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> surgeries({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/surgeries', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> prescriptions({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/prescriptions', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> inventoryProducts({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/inventory/products', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> inventoryMovements({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/inventory/movements', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> schedule({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/schedule', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> invoices({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/invoices', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> payments({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/payments', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> media({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/media', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> staff({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/staff', page: page, search: search);

  Future<RemoteDashboardSummary> dashboard() async =>
      RemoteDashboardSummary.fromJson(
        await _client.get('/api/v1/dashboard/summary'),
      );

  Future<RemotePage<Map<String, dynamic>>> _generic(
    String path, {
    required int page,
    String? search,
  }) async {
    final response = await _client.get(
      _path(path, {
        'page': '$page',
        'pageSize': '25',
        if (search?.isNotEmpty ?? false) 'search': search!,
      }),
    );
    return _page(response, (value) => value);
  }

  RemotePage<T> _page<T>(
    Map<String, dynamic> value,
    T Function(Map<String, dynamic>) parser,
  ) => RemotePage(
    items: (value['items'] as List<dynamic>? ?? const [])
        .map((item) => parser(Map<String, dynamic>.from(item as Map)))
        .toList(),
    page: _int(value['page']),
    pageSize: _int(value['pageSize']),
    total: _int(value['total']),
    hasNextPage: value['hasNextPage'] == true,
  );
}

String _path(String path, Map<String, String> query) =>
    '$path?${query.entries.map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}').join('&')}';
DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
int _int(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
num _num(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;

String encodeCloudPayload(Object value) => jsonEncode(value);
