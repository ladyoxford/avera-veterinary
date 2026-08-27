import 'dart:convert';

import '../models/reminder_event.dart';
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
    this.ownerId,
    this.breed,
    this.sex,
    this.ownerEmail,
    this.ownerAddress,
    this.imagePlaceholder,
    this.photoUrl,
    this.dateOfBirth,
    this.isDateOfBirthEstimated = false,
    this.originalAgeValue,
    this.originalAgeUnit,
    this.ageRecordedAt,
    this.currentWeightKg,
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
  final String? ownerId;
  final String? breed;
  final String? sex;
  final String? ownerEmail;
  final String? ownerAddress;
  final String? imagePlaceholder;
  final String? photoUrl;
  final DateTime? dateOfBirth;
  final bool isDateOfBirthEstimated;
  final int? originalAgeValue;
  final String? originalAgeUnit;
  final DateTime? ageRecordedAt;
  final num? currentWeightKg;
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
    ownerId: value['owner_id'] as String?,
    breed: value['breed'] as String?,
    sex: value['sex'] as String?,
    ownerEmail: value['owner_email'] as String?,
    ownerAddress: _ownerAddress(value),
    imagePlaceholder: value['image_placeholder'] as String?,
    photoUrl: value['profile_photo_url'] as String?,
    dateOfBirth: _date(value['date_of_birth']),
    isDateOfBirthEstimated:
        value['is_date_of_birth_estimated'] as bool? ?? false,
    originalAgeValue: _nullableInt(value['original_age_value']),
    originalAgeUnit: value['original_age_unit'] as String?,
    ageRecordedAt: _date(value['age_recorded_at']),
    currentWeightKg: value['current_weight_kg'] == null
        ? null
        : _num(value['current_weight_kg']),
    registeredAt: _date(value['registered_at']),
    revision: _nullableInt(value['revision']),
  );

  Map<String, dynamic> toJson() => {
    'patient_id': id,
    'hospital_number': hospitalNumber,
    'name': name,
    'species': species,
    'status': status,
    'owner_name': ownerName,
    'owner_phone': ownerPhone,
    'owner_id': ownerId,
    'breed': breed,
    'sex': sex,
    'owner_email': ownerEmail,
    'owner_address': ownerAddress,
    'image_placeholder': imagePlaceholder,
    'profile_photo_url': photoUrl,
    'date_of_birth': dateOfBirth?.toIso8601String(),
    'is_date_of_birth_estimated': isDateOfBirthEstimated,
    'original_age_value': originalAgeValue,
    'original_age_unit': originalAgeUnit,
    'age_recorded_at': ageRecordedAt?.toIso8601String(),
    'current_weight_kg': currentWeightKg,
    'registered_at': registeredAt?.toIso8601String(),
    'revision': revision,
  };

  bool hasSameBillingOwnerAs(RemotePatient other) {
    final thisOwnerId = ownerId?.trim();
    final otherOwnerId = other.ownerId?.trim();
    if (thisOwnerId?.isNotEmpty == true &&
        otherOwnerId?.isNotEmpty == true &&
        thisOwnerId == otherOwnerId) {
      return true;
    }
    final thisPhone = _billingPhone(ownerPhone);
    final otherPhone = _billingPhone(other.ownerPhone);
    if (thisPhone.length >= 7 && thisPhone == otherPhone) return true;
    final thisEmail = ownerEmail?.trim().toLowerCase() ?? '';
    final otherEmail = other.ownerEmail?.trim().toLowerCase() ?? '';
    return thisEmail.isNotEmpty && thisEmail == otherEmail;
  }

  static String _billingPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }
}

class RemoteAppointmentDetail {
  const RemoteAppointmentDetail({
    required this.id,
    required this.patientId,
    required this.scheduledAt,
    required this.visitType,
    required this.status,
    required this.revision,
    this.patient,
    this.notes,
    this.assignedStaffId,
    this.assignedStaffName,
    this.assignedStaffTitle,
    this.updatedAt,
  });

  final String id;
  final String patientId;
  final DateTime scheduledAt;
  final String visitType;
  final String status;
  final int revision;

  final RemotePatient? patient;
  final String? notes;
  final String? assignedStaffId;
  final String? assignedStaffName;
  final String? assignedStaffTitle;
  final DateTime? updatedAt;

  bool get hasPatient => patient != null;

  factory RemoteAppointmentDetail.fromJson(Map<String, dynamic> value) {
    final appointment = value['appointment'] is Map
        ? Map<String, dynamic>.from(value['appointment'] as Map)
        : value;
    final patientName = appointment['patient_name'] as String?;
    return RemoteAppointmentDetail(
      id: appointment['schedule_entry_id'] as String,
      patientId: appointment['patient_id'] as String,
      scheduledAt:
          _date(appointment['scheduled_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      visitType: appointment['visit_type'] as String? ?? 'Appointment',
      status: appointment['status'] as String? ?? 'Confirmed',
      revision: _nullableInt(appointment['revision']) ?? 1,
      patient: patientName == null
          ? null
          : RemotePatient.fromJson({
              ...appointment,
              'name': patientName,
              'status': appointment['patient_status'] ?? 'Active',
            }),
      notes: appointment['notes'] as String?,
      assignedStaffId: appointment['assigned_staff_id'] as String?,
      assignedStaffName: appointment['assigned_staff_name'] as String?,
      assignedStaffTitle: appointment['assigned_staff_title'] as String?,
      updatedAt: _date(appointment['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'schedule_entry_id': id,
    'patient_id': patientId,
    'scheduled_at': scheduledAt.toIso8601String(),
    'visit_type': visitType,
    'status': status,
    'revision': revision,
    'notes': notes,
    'assigned_staff_id': assignedStaffId,
    'assigned_staff_name': assignedStaffName,
    'assigned_staff_title': assignedStaffTitle,
    'updated_at': updatedAt?.toIso8601String(),
    if (patient != null) ...{
      ...patient!.toJson(),
      'patient_name': patient!.name,
      'patient_status': patient!.status,
    },
  };
}

String? _ownerAddress(Map<String, dynamic> value) {
  final parts = <String>[
    if ((value['owner_address'] as String?)?.trim().isNotEmpty ?? false)
      (value['owner_address'] as String).trim(),
    if ((value['owner_city'] as String?)?.trim().isNotEmpty ?? false)
      (value['owner_city'] as String).trim(),
    if ((value['owner_state'] as String?)?.trim().isNotEmpty ?? false)
      (value['owner_state'] as String).trim(),
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

class RemoteProductUnit {
  const RemoteProductUnit({
    required this.id,
    required this.label,
    required this.isBaseUnit,
    required this.conversionToBase,
    required this.sellingPrice,
    this.revision,
  });

  final String id;
  final String label;
  final bool isBaseUnit;
  final int conversionToBase;
  final num sellingPrice;
  final int? revision;

  factory RemoteProductUnit.fromJson(Map<String, dynamic> value) =>
      RemoteProductUnit(
        id: value['product_unit_id'] as String,
        label: value['unit_label'] as String? ?? 'unit',
        isBaseUnit: value['is_base_unit'] as bool? ?? false,
        conversionToBase: _int(value['conversion_to_base']),
        sellingPrice: _num(value['selling_price']),
        revision: _nullableInt(value['revision']),
      );

  Map<String, dynamic> toJson() => {
    'product_unit_id': id,
    'unit_label': label,
    'is_base_unit': isBaseUnit,
    'conversion_to_base': conversionToBase,
    'selling_price': sellingPrice,
    'revision': revision,
  };
}

class RemoteInventoryItem {
  const RemoteInventoryItem({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.quantity,
    required this.reorderLevel,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.status,
    this.genericName,
    this.brandName,
    this.manufacturer,
    this.supplier,
    this.sku,
    this.barcode,
    this.shortDescription,
    this.detailedDescription,
    this.dosageForm,
    this.packSize,
    this.batchNumber,
    this.expiryDate,
    this.createdAt,
    this.updatedAt,
    this.revision,
    this.baseUnitLabel = 'unit',
    this.activeIngredient,
    this.dosageAndRoute,
    this.withdrawalMeat,
    this.withdrawalMilk,
    this.withdrawalEggs,
    this.withdrawalOther,
    this.warnings,
    this.contraindications,
    this.adverseEffects,
    this.storageConditions,
    this.publicDisplayName,
    this.availableToPublic = false,
    this.isSellable = true,
    this.isArchived = false,
    this.productUnits = const [],
    this.imageUrl,
  });

  final String id;
  final String name;
  final String categoryId;
  final String categoryName;
  final int quantity;
  final int reorderLevel;
  final num purchasePrice;
  final num sellingPrice;
  final String status;
  final String? genericName;
  final String? brandName;
  final String? manufacturer;
  final String? supplier;
  final String? sku;
  final String? barcode;
  final String? shortDescription;
  final String? detailedDescription;
  final String? dosageForm;
  final String? packSize;
  final String? batchNumber;
  final DateTime? expiryDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? revision;
  final String baseUnitLabel;
  final String? activeIngredient;
  final String? dosageAndRoute;
  final String? withdrawalMeat;
  final String? withdrawalMilk;
  final String? withdrawalEggs;
  final String? withdrawalOther;
  final String? warnings;
  final String? contraindications;
  final String? adverseEffects;
  final String? storageConditions;
  final String? publicDisplayName;
  final bool availableToPublic;
  final bool isSellable;
  final bool isArchived;
  final List<RemoteProductUnit> productUnits;
  final String? imageUrl;

  factory RemoteInventoryItem.fromJson(Map<String, dynamic> value) {
    final categoryName = value['category'] as String? ?? 'Other';
    return RemoteInventoryItem(
      id: value['inventory_product_id'] as String,
      name: value['name'] as String? ?? 'Unnamed item',
      categoryId:
          value['category_key'] as String? ??
          _canonicalInventoryCategory(categoryName),
      categoryName: categoryName,
      quantity: _int(value['quantity']),
      reorderLevel: _int(value['reorder_level']),
      purchasePrice: _num(value['purchase_price']),
      sellingPrice: _num(value['selling_price']),
      status: value['status'] as String? ?? 'Active',
      genericName: value['generic_name'] as String?,
      manufacturer: value['manufacturer'] as String?,
      supplier: value['supplier'] as String?,
      batchNumber: value['batch_number'] as String?,
      expiryDate: _date(value['expiry_date']),
      createdAt: _date(value['created_at']),
      updatedAt: _date(value['updated_at']),
      revision: _nullableInt(value['revision']),
      brandName: value['brand_name'] as String?,
      baseUnitLabel: value['base_unit_label'] as String? ?? 'unit',
      sku: value['sku'] as String?,
      barcode: value['barcode'] as String?,
      shortDescription: value['short_description'] as String?,
      detailedDescription: value['detailed_description'] as String?,
      dosageForm: value['dosage_form'] as String?,
      packSize: value['pack_size'] as String?,
      activeIngredient: value['active_ingredient'] as String?,
      dosageAndRoute: value['dosage_and_route'] as String?,
      withdrawalMeat: value['withdrawal_meat'] as String?,
      withdrawalMilk: value['withdrawal_milk'] as String?,
      withdrawalEggs: value['withdrawal_eggs'] as String?,
      withdrawalOther: value['withdrawal_other'] as String?,
      warnings: value['warnings'] as String?,
      contraindications: value['contraindications'] as String?,
      adverseEffects: value['adverse_effects'] as String?,
      storageConditions: value['storage_conditions'] as String?,
      publicDisplayName: value['public_display_name'] as String?,
      availableToPublic: value['available_to_public'] as bool? ?? false,
      isSellable: value['is_sellable'] as bool? ?? true,
      isArchived: value['is_archived'] as bool? ?? false,
      imageUrl: value['image_url'] as String?,
      productUnits: (value['product_units'] as List<dynamic>? ?? const [])
          .map(
            (unit) => RemoteProductUnit.fromJson(
              Map<String, dynamic>.from(unit as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'inventory_product_id': id,
    'name': name,
    'category_key': categoryId,
    'category': categoryName,
    'quantity': quantity,
    'reorder_level': reorderLevel,
    'purchase_price': purchasePrice,
    'selling_price': sellingPrice,
    'status': status,
    'generic_name': genericName,
    'brand_name': brandName,
    'manufacturer': manufacturer,
    'supplier': supplier,
    'sku': sku,
    'barcode': barcode,
    'short_description': shortDescription,
    'detailed_description': detailedDescription,
    'dosage_form': dosageForm,
    'pack_size': packSize,
    'batch_number': batchNumber,
    'expiry_date': expiryDate?.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'revision': revision,
    'base_unit_label': baseUnitLabel,
    'active_ingredient': activeIngredient,
    'dosage_and_route': dosageAndRoute,
    'withdrawal_meat': withdrawalMeat,
    'withdrawal_milk': withdrawalMilk,
    'withdrawal_eggs': withdrawalEggs,
    'withdrawal_other': withdrawalOther,
    'warnings': warnings,
    'contraindications': contraindications,
    'adverse_effects': adverseEffects,
    'storage_conditions': storageConditions,
    'public_display_name': publicDisplayName,
    'available_to_public': availableToPublic,
    'is_sellable': isSellable,
    'is_archived': isArchived,
    'image_url': imageUrl,
    'product_units': productUnits.map((unit) => unit.toJson()).toList(),
  };
}

class RemoteConsultationCreation {
  const RemoteConsultationCreation({
    required this.id,
    required this.patientId,
    required this.submissionId,
    required this.duplicateSubmission,
  });

  final String id;
  final String patientId;
  final String submissionId;
  final bool duplicateSubmission;

  factory RemoteConsultationCreation.fromJson(Map<String, dynamic> value) {
    final consultation = Map<String, dynamic>.from(
      value['consultation'] as Map,
    );
    return RemoteConsultationCreation(
      id: consultation['consultation_id'] as String,
      patientId: consultation['patient_id'] as String,
      submissionId: value['submissionId'] as String,
      duplicateSubmission: value['duplicateSubmission'] == true,
    );
  }
}

class RemoteVaccinationRecord {
  const RemoteVaccinationRecord({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.hospitalNumber,
    required this.vaccineName,
    required this.status,
    required this.administeredAt,
    this.nextDueAt,
    this.species,
    this.breed,
    this.ownerName,
    this.ownerPhone,
    this.manufacturer,
    this.batchNumber,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String hospitalNumber;
  final String vaccineName;
  final String status;
  final DateTime administeredAt;
  final DateTime? nextDueAt;
  final String? species;
  final String? breed;
  final String? ownerName;
  final String? ownerPhone;
  final String? manufacturer;
  final String? batchNumber;

  factory RemoteVaccinationRecord.fromJson(Map<String, dynamic> value) =>
      RemoteVaccinationRecord(
        id: value['vaccination_id'] as String,
        patientId: value['patient_id'] as String,
        patientName: value['patient_name']?.toString() ?? 'Patient',
        hospitalNumber: value['hospital_number']?.toString() ?? '',
        vaccineName: value['vaccine_name']?.toString() ?? 'Vaccination',
        status: value['status']?.toString() ?? 'Completed',
        administeredAt:
            _date(value['administered_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        nextDueAt: _date(value['next_due_at']),
        species: value['species']?.toString(),
        breed: value['breed']?.toString(),
        ownerName: value['owner_name']?.toString(),
        ownerPhone: value['owner_phone']?.toString(),
        manufacturer: value['manufacturer']?.toString(),
        batchNumber: value['batch_number']?.toString(),
      );

  Map<String, dynamic> toJson() => {
    'vaccination_id': id,
    'patient_id': patientId,
    'patient_name': patientName,
    'hospital_number': hospitalNumber,
    'vaccine_name': vaccineName,
    'status': status,
    'administered_at': administeredAt.toIso8601String(),
    'next_due_at': nextDueAt?.toIso8601String(),
    'species': species,
    'breed': breed,
    'owner_name': ownerName,
    'owner_phone': ownerPhone,
    'manufacturer': manufacturer,
    'batch_number': batchNumber,
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

class RemoteRevenueProfitSummary {
  const RemoteRevenueProfitSummary({
    required this.revenue,
    required this.cost,
    required this.clinicRevenue,
    required this.farmRevenue,
    required this.transactionCount,
    required this.missingCostLines,
  });

  final double revenue;
  final double cost;
  final double clinicRevenue;
  final double farmRevenue;
  final int transactionCount;
  final int missingCostLines;

  factory RemoteRevenueProfitSummary.fromJson(Map<String, dynamic> value) =>
      RemoteRevenueProfitSummary(
        revenue: _num(value['revenue']).toDouble(),
        cost: _num(value['cost']).toDouble(),
        clinicRevenue: _num(value['clinic_revenue']).toDouble(),
        farmRevenue: _num(value['farm_revenue']).toDouble(),
        transactionCount: _int(value['transaction_count']),
        missingCostLines: _int(value['missing_cost_lines']),
      );
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

  Future<RemotePatient> updatePatientStatus({
    required String patientId,
    required String status,
    String? reason,
  }) async {
    final response = await _client.patch(
      '/api/v1/patients/$patientId/status',
      body: {
        'status': status,
        if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
      },
    );
    return RemotePatient.fromJson(
      Map<String, dynamic>.from(response['patient'] as Map),
    );
  }

  Future<RemotePatient> updatePatientPhoto({
    required String patientId,
    required String contentType,
    required String base64Data,
  }) async {
    final response = await _client.post(
      '/api/v1/patients/$patientId/profile-photo',
      authenticated: true,
      body: {'contentType': contentType, 'data': base64Data},
    );
    return RemotePatient.fromJson(
      Map<String, dynamic>.from(response['patient'] as Map),
    );
  }

  Future<RemotePatient> patient(String patientId) async {
    final response = await _client.get('/api/v1/patients/$patientId');
    return RemotePatient.fromJson(
      Map<String, dynamic>.from(response['patient'] as Map),
    );
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

  Future<RemoteConsultationCreation> createConsultation(
    Map<String, dynamic> payload,
  ) async => RemoteConsultationCreation.fromJson(
    await _client.post(
      '/api/v1/consultations',
      body: payload,
      authenticated: true,
    ),
  );

  Future<Map<String, dynamic>> consultation(String consultationId) async {
    final response = await _client.get('/api/v1/consultations/$consultationId');
    return Map<String, dynamic>.from(response['consultation'] as Map);
  }

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

  Future<RemotePage<RemoteVaccinationRecord>> vaccinationSchedule({
    int page = 1,
    int pageSize = 100,
    String? search,
  }) async {
    final response = await _client.get(
      _path('/api/v1/vaccinations', {
        'page': '$page',
        'pageSize': '$pageSize',
        if (search?.isNotEmpty ?? false) 'search': search!,
      }),
    );
    return _page(response, RemoteVaccinationRecord.fromJson);
  }

  Future<Map<String, dynamic>> createVaccination(
    Map<String, dynamic> payload,
  ) async => Map<String, dynamic>.from(
    await _client.post(
      '/api/v1/vaccinations',
      body: payload,
      authenticated: true,
    ),
  );

  Future<Map<String, dynamic>> vaccination(String vaccinationId) async =>
      Map<String, dynamic>.from(
        await _client.get('/api/v1/vaccinations/$vaccinationId'),
      );
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

  Future<RemotePage<Map<String, dynamic>>> clinicalOperations({
    required String operationType,
    int page = 1,
    String? search,
    String? status,
  }) async {
    final response = await _client.get(
      _path('/api/v1/clinical-operations', {
        'page': '$page',
        'pageSize': '100',
        'operationType': operationType,
        if (search?.isNotEmpty ?? false) 'search': search!,
        if (status?.isNotEmpty ?? false) 'status': status!,
      }),
    );
    return _page(response, (value) => value);
  }

  Future<Map<String, dynamic>> createClinicalOperation(
    Map<String, dynamic> payload,
  ) async => Map<String, dynamic>.from(
    await _client.post(
      '/api/v1/clinical-operations',
      body: payload,
      authenticated: true,
    ),
  );

  Future<Map<String, dynamic>> clinicalOperation(String operationId) async =>
      Map<String, dynamic>.from(
        await _client.get('/api/v1/clinical-operations/$operationId'),
      );

  Future<Map<String, dynamic>> updateClinicalOperationStatus({
    required String operationId,
    required String status,
    String? reason,
  }) async => Map<String, dynamic>.from(
    await _client.patch(
      '/api/v1/clinical-operations/$operationId/status',
      body: {
        'status': status,
        if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
      },
    ),
  );
  Future<RemotePage<RemoteInventoryItem>> inventoryProducts({
    int page = 1,
    int pageSize = 100,
    String? search,
  }) async {
    final response = await _client.get(
      _path('/api/v1/inventory/products', {
        'page': '$page',
        'pageSize': '$pageSize',
        if (search?.isNotEmpty ?? false) 'search': search!,
      }),
    );
    return _page(response, RemoteInventoryItem.fromJson);
  }

  Future<RemoteInventoryItem> createInventoryItem(
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      '/api/v1/inventory/products',
      body: payload,
      authenticated: true,
    );
    return RemoteInventoryItem.fromJson(
      Map<String, dynamic>.from(response['item'] as Map),
    );
  }

  Future<RemoteInventoryItem> updateInventoryItem({
    required String inventoryProductId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.patch(
      '/api/v1/inventory/products/$inventoryProductId',
      body: payload,
    );
    return RemoteInventoryItem.fromJson(
      Map<String, dynamic>.from(response['item'] as Map),
    );
  }

  Future<RemoteInventoryItem> addInventoryStock({
    required String inventoryProductId,
    required int quantityToAdd,
    String? batchNumber,
    DateTime? expiryDate,
    double? purchasePrice,
  }) async {
    final response = await _client.post(
      '/api/v1/inventory/products/$inventoryProductId/add-stock',
      authenticated: true,
      body: {
        'quantityToAdd': quantityToAdd,
        if (batchNumber?.trim().isNotEmpty == true)
          'batchNumber': batchNumber!.trim(),
        if (expiryDate != null)
          'expiryDate': expiryDate.toIso8601String().split('T').first,
        if (purchasePrice != null) 'purchasePrice': purchasePrice,
      },
    );
    return RemoteInventoryItem.fromJson(
      Map<String, dynamic>.from(response['item'] as Map),
    );
  }

  Future<RemoteInventoryItem> updateInventoryItemPhoto({
    required String inventoryProductId,
    required String contentType,
    required String base64Data,
  }) async {
    final response = await _client.post(
      '/api/v1/inventory/products/$inventoryProductId/photo',
      authenticated: true,
      body: {'contentType': contentType, 'data': base64Data},
    );
    return RemoteInventoryItem.fromJson(
      Map<String, dynamic>.from(response['item'] as Map),
    );
  }

  Future<RemoteInventoryItem> replaceInventoryProductUnits({
    required String inventoryProductId,
    required List<Map<String, dynamic>> units,
  }) async {
    final response = await _client.put(
      '/api/v1/inventory/products/$inventoryProductId/units',
      body: {'units': units},
    );
    return RemoteInventoryItem.fromJson(
      Map<String, dynamic>.from(response['item'] as Map),
    );
  }

  Future<Map<String, dynamic>> createInventoryReorderRequest({
    required String inventoryProductId,
    required int requestedQuantity,
    String? productUnitId,
  }) async => Map<String, dynamic>.from(
    await _client.post(
      '/api/v1/inventory/products/$inventoryProductId/reorder-requests',
      body: {
        'requestedQuantity': requestedQuantity,
        if (productUnitId != null) 'productUnitId': productUnitId,
      },
      authenticated: true,
    ),
  );

  Future<List<RemoteInventoryItem>> relatedInventoryProducts(
    String inventoryProductId,
  ) async {
    final response = await _client.get(
      '/api/v1/inventory/products/$inventoryProductId/related',
    );
    return (response['items'] as List<dynamic>? ?? const [])
        .map(
          (item) => RemoteInventoryItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<RemotePage<Map<String, dynamic>>> inventoryMovements({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/inventory/movements', page: page, search: search);
  Future<RemotePage<Map<String, dynamic>>> schedule({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/schedule', page: page, search: search);

  Future<RemoteAppointmentDetail> appointment(String appointmentId) async {
    final response = await _client.get('/api/v1/schedule/$appointmentId');
    return RemoteAppointmentDetail.fromJson(response);
  }

  Future<Map<String, dynamic>> createAppointment(
    Map<String, dynamic> payload,
  ) async => Map<String, dynamic>.from(
    await _client.post('/api/v1/schedule', body: payload, authenticated: true),
  );

  Future<RemoteAppointmentDetail> updateAppointment({
    required String appointmentId,
    required Map<String, dynamic> payload,
  }) async => RemoteAppointmentDetail.fromJson(
    await _client.patch('/api/v1/schedule/$appointmentId', body: payload),
  );

  Future<RemoteAppointmentDetail> cancelAppointment({
    required String appointmentId,
    required int revision,
  }) async => RemoteAppointmentDetail.fromJson(
    await _client.post(
      '/api/v1/schedule/$appointmentId/cancel',
      body: {'revision': revision},
      authenticated: true,
    ),
  );

  Future<Map<String, dynamic>> updateConsultation({
    required String consultationId,
    required Map<String, dynamic> payload,
  }) async => Map<String, dynamic>.from(
    await _client.patch('/api/v1/consultations/$consultationId', body: payload),
  );
  Future<RemotePage<Map<String, dynamic>>> invoices({
    int page = 1,
    int pageSize = 100,
    String? search,
  }) => _generic(
    '/api/v1/invoices',
    page: page,
    pageSize: pageSize,
    search: search,
  );

  Future<Map<String, dynamic>> createInvoice(
    Map<String, dynamic> payload,
  ) async => Map<String, dynamic>.from(
    await _client.post('/api/v1/invoices', body: payload, authenticated: true),
  );
  Future<Map<String, dynamic>> farmContext(String farmId) async {
    final response = await _client.get('/api/v1/farms/$farmId/context');
    return Map<String, dynamic>.from(response['farmContext'] as Map);
  }

  Future<Map<String, dynamic>> saveFarmContext({
    required String farmId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.put(
      '/api/v1/farms/$farmId/context',
      body: payload,
      authenticated: true,
    );
    return Map<String, dynamic>.from(response['farmContext'] as Map);
  }

  Future<Map<String, dynamic>> invoice(String invoiceId) async =>
      Map<String, dynamic>.from(
        await _client.get('/api/v1/invoices/$invoiceId'),
      );
  Future<Map<String, dynamic>> recordInvoicePayment({
    required String invoiceId,
    required Map<String, dynamic> payload,
  }) async => Map<String, dynamic>.from(
    await _client.post(
      '/api/v1/invoices/$invoiceId/payments',
      body: payload,
      authenticated: true,
    ),
  );
  Future<RemotePage<Map<String, dynamic>>> payments({
    int page = 1,
    String? search,
  }) => _generic('/api/v1/payments', page: page, search: search);
  Future<RemoteRevenueProfitSummary> revenueProfitSummary({
    DateTime? from,
    DateTime? to,
  }) async => RemoteRevenueProfitSummary.fromJson(
    await _client.get(
      _path('/api/v1/billing/revenue-summary', {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      }),
    ),
  );
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

  Future<ReminderFeed> reminders() async =>
      ReminderFeed.fromJson(await _client.get('/api/v1/reminders'));

  Future<RemotePage<RemoteNotificationItem>> notifications({
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _client.get(
      _path('/api/v1/notifications', {
        'page': '$page',
        'pageSize': '$pageSize',
      }),
    );
    return _page(response, RemoteNotificationItem.fromJson);
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client.patch('/api/v1/notifications/$notificationId/read');
  }

  Future<void> dismissNotification(String notificationId) async {
    await _client.patch('/api/v1/notifications/$notificationId/dismiss');
  }

  Future<RemotePage<Map<String, dynamic>>> activity({
    int page = 1,
    int pageSize = 50,
    String? search,
    String? module,
    DateTime? from,
    DateTime? until,
  }) async {
    final response = await _client.get(
      _path('/api/v1/activity', {
        'page': '$page',
        'pageSize': '$pageSize',
        if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
        if (module?.trim().isNotEmpty == true) 'module': module!.trim(),
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (until != null) 'to': until.toUtc().toIso8601String(),
      }),
    );
    return _page(response, (value) => value);
  }

  Future<RemotePage<Map<String, dynamic>>> patientClinicalOperations(
    String patientId, {
    required String operationType,
    int page = 1,
  }) async {
    final response = await _client.get(
      _path('/api/v1/patients/$patientId/clinical-operations', {
        'page': '$page',
        'pageSize': '25',
        'operationType': operationType,
      }),
    );
    return _page(response, (value) => value);
  }

  Future<RemotePage<Map<String, dynamic>>> _generic(
    String path, {
    required int page,
    int pageSize = 25,
    String? search,
  }) async {
    final response = await _client.get(
      _path(path, {
        'page': '$page',
        'pageSize': '$pageSize',
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
int? _nullableInt(Object? value) {
  if (value == null) return null;
  return value is int ? value : int.tryParse('$value');
}

num _num(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;

String _canonicalInventoryCategory(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('vaccine')) return 'vaccines';
  if (normalized.contains('drug') || normalized.contains('pharmacy')) {
    return 'drugs';
  }
  if (normalized.contains('supplement')) return 'supplements';
  if (normalized.contains('food')) return 'pet_food';
  if (normalized.contains('accessor')) return 'pet_accessories';
  if (normalized.contains('groom')) return 'grooming_supplies';
  if (normalized.contains('laboratory') && normalized.contains('equipment')) {
    return 'laboratory_equipment';
  }
  if (normalized.contains('laboratory')) return 'laboratory_consumables';
  if (normalized.contains('surg')) return 'surgical_supplies';
  if (normalized.contains('consumable')) return 'clinical_consumables';
  if (normalized.contains('equipment')) return 'general_equipment';
  return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

String encodeCloudPayload(Object value) => jsonEncode(value);
