import '../subscription/subscription_plan_config.dart';

export '../subscription/subscription_plan_config.dart' show SubscriptionPlan;

enum SubscriptionStatus {
  active,
  trial,
  gracePeriod,
  expired,
  suspended,
  cancelled;

  static SubscriptionStatus fromStorage(String value) {
    return SubscriptionStatus.values.firstWhere(
      (status) => status.name.toLowerCase() == value.trim().toLowerCase(),
      orElse: () => SubscriptionStatus.active,
    );
  }
}

enum FeatureImplementationStatus {
  available,
  limited,
  comingSoon,
  planned,
  beta;

  static FeatureImplementationStatus fromStorage(String value) {
    return FeatureImplementationStatus.values.firstWhere(
      (status) => status.name.toLowerCase() == value.trim().toLowerCase(),
      orElse: () => FeatureImplementationStatus.available,
    );
  }

  String get label => switch (this) {
    FeatureImplementationStatus.available => 'Included',
    FeatureImplementationStatus.limited => 'Limited',
    FeatureImplementationStatus.comingSoon => 'Coming Soon',
    FeatureImplementationStatus.planned => 'Planned',
    FeatureImplementationStatus.beta => 'Beta',
  };
}

enum FeatureAccessReason {
  allowed,
  permissionDenied,
  subscriptionRequired,
  featureNotInPlan,
  usageLimitReached,
  subscriptionExpired,
  subscriptionSuspended,
  trialExpired,
  featureComingSoon,
}

/// Product-facing capabilities. Enum values remain stable local keys; the
/// database catalogue uses [FeatureEntitlement.key] rather than enum indexes.
enum AveraFeature {
  patientRecords,
  consultations,
  schedule,
  vaccinations,
  inventory,
  billing,
  documents,
  laboratory,
  prescriptions,
  imaging,
  reports,
  vera,
  hospitalization,
  treatmentBoard,
  surgery,
  corporateAnalytics,
  advancedLaboratory,
  advancedInventory,
  multiLocationInventory,
  clientPortal,
  onlineBooking,
  emailReminders,
  smsReminders,
  whatsappReminders,
  staffAnalytics,
  automation,
  centralInventory,
  corporateDashboard,
  auditCentre,
  advancedPermissionBuilder,
  veraBasic,
  veraClinical,
  veraEnterprise,
}

class SubscriptionPlanDefinition {
  const SubscriptionPlanDefinition({
    required this.plan,
    required this.positioning,
    required this.targetCustomer,
    required this.monthlyPriceLabel,
    required this.annualPriceLabel,
    required this.staffLimit,
    required this.patientLimit,
    required this.clinicLimit,
    required this.storageLabel,
    required this.veraLevel,
    this.isMostPopular = false,
    this.isContactSales = false,
  });

  final SubscriptionPlan plan;
  final String positioning;
  final String targetCustomer;
  final String monthlyPriceLabel;
  final String annualPriceLabel;
  final int? staffLimit;
  final int? patientLimit;
  final int? clinicLimit;
  final String storageLabel;
  final String veraLevel;
  final bool isMostPopular;
  final bool isContactSales;
}

class FeatureEntitlement {
  const FeatureEntitlement({
    required this.feature,
    required this.key,
    required this.label,
    required this.category,
    required this.minimumPlan,
    required this.reason,
    this.implementationStatus = FeatureImplementationStatus.available,
    this.numericLimit,
  });

  final AveraFeature feature;
  final String key;
  final String label;
  final String category;
  final SubscriptionPlan minimumPlan;
  final String reason;
  final FeatureImplementationStatus implementationStatus;
  final int? numericLimit;
}

class FeatureAccessResult {
  const FeatureAccessResult({
    required this.allowed,
    required this.reason,
    required this.entitlement,
    required this.currentPlan,
    required this.requiredPlan,
    required this.subscriptionStatus,
    required this.implementationStatus,
    this.usage,
    this.limit,
  });

  final bool allowed;
  final FeatureAccessReason reason;
  final FeatureEntitlement entitlement;
  final SubscriptionPlan currentPlan;
  final SubscriptionPlan requiredPlan;
  final SubscriptionStatus subscriptionStatus;
  final FeatureImplementationStatus implementationStatus;
  final int? usage;
  final int? limit;

  bool get upgradeAvailable =>
      !allowed && requiredPlan.index > currentPlan.index;
  bool get isComingSoon =>
      implementationStatus == FeatureImplementationStatus.comingSoon ||
      implementationStatus == FeatureImplementationStatus.planned ||
      implementationStatus == FeatureImplementationStatus.beta;
}

class FeatureAccessDenied implements Exception {
  const FeatureAccessDenied(this.result);

  final FeatureAccessResult result;

  FeatureEntitlement get entitlement => result.entitlement;

  @override
  String toString() =>
      '${entitlement.label} requires the ${entitlement.minimumPlan.label} plan.';
}

/// Central capability catalogue used by Drift seeding, UI gates and local
/// repository enforcement. Remote entitlements can later hydrate the same
/// contract without scattering plan checks through the application.
class FeatureGateService {
  const FeatureGateService._();

  static const planDefinitions = <SubscriptionPlan, SubscriptionPlanDefinition>{
    SubscriptionPlan.starter: SubscriptionPlanDefinition(
      plan: SubscriptionPlan.starter,
      positioning: 'Digital clinic management.',
      targetCustomer: 'New and single-clinic veterinary practices',
      monthlyPriceLabel: 'Local development pricing',
      annualPriceLabel: 'Annual pricing available',
      staffLimit: 5,
      patientLimit: 1500,
      clinicLimit: 1,
      storageLabel: '5 GB logical local storage',
      veraLevel: 'Vera Basic',
    ),
    SubscriptionPlan.professional: SubscriptionPlanDefinition(
      plan: SubscriptionPlan.professional,
      positioning: 'Digital clinic management with an AI clinical assistant.',
      targetCustomer: 'Growing hospitals and mixed-animal practices',
      monthlyPriceLabel: 'Local development pricing',
      annualPriceLabel: 'Annual pricing available',
      staffLimit: 25,
      patientLimit: null,
      clinicLimit: 3,
      storageLabel: '50 GB logical local storage',
      veraLevel: 'Vera Clinical Assistant',
      isMostPopular: true,
    ),
    SubscriptionPlan.enterprise: SubscriptionPlanDefinition(
      plan: SubscriptionPlan.enterprise,
      positioning: 'An AI-powered veterinary hospital operating system.',
      targetCustomer: 'Hospital groups, referral centres and institutions',
      monthlyPriceLabel: 'Contact sales',
      annualPriceLabel: 'Custom annual agreement',
      staffLimit: null,
      patientLimit: null,
      clinicLimit: null,
      storageLabel: 'Enterprise logical storage',
      veraLevel: 'Vera Intelligence Platform',
      isContactSales: true,
    ),
  };

  static const _entitlements = <AveraFeature, FeatureEntitlement>{
    AveraFeature.patientRecords: FeatureEntitlement(
      feature: AveraFeature.patientRecords,
      key: 'patients.basic',
      label: 'Patient records',
      category: 'Core practice management',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Maintain an organised patient and owner register.',
    ),
    AveraFeature.consultations: FeatureEntitlement(
      feature: AveraFeature.consultations,
      key: 'consultations.basic',
      label: 'Consultations',
      category: 'Medical Files',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Capture clinical consultations and follow-up care.',
    ),
    AveraFeature.schedule: FeatureEntitlement(
      feature: AveraFeature.schedule,
      key: 'schedule.basic',
      label: 'Schedule',
      category: 'Core practice management',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Coordinate clinic visits and reminders.',
    ),
    AveraFeature.vaccinations: FeatureEntitlement(
      feature: AveraFeature.vaccinations,
      key: 'vaccinations.basic',
      label: 'Vaccinations',
      category: 'Medical Files',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Manage vaccination, deworming, and preventive care records.',
    ),
    AveraFeature.inventory: FeatureEntitlement(
      feature: AveraFeature.inventory,
      key: 'inventory.basic',
      label: 'Basic inventory',
      category: 'Inventory',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Track clinic stock and product usage.',
    ),
    AveraFeature.billing: FeatureEntitlement(
      feature: AveraFeature.billing,
      key: 'billing.basic',
      label: 'Billing and payments',
      category: 'Billing and finance',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Record invoices, payments, and outstanding balances.',
    ),
    AveraFeature.documents: FeatureEntitlement(
      feature: AveraFeature.documents,
      key: 'medical_file.basic',
      label: 'Medical documents',
      category: 'Medical Files',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Keep medical documents with each patient file.',
    ),
    AveraFeature.laboratory: FeatureEntitlement(
      feature: AveraFeature.laboratory,
      key: 'laboratory.basic',
      label: 'Basic laboratory',
      category: 'Laboratory',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Create and track routine laboratory requests.',
    ),
    AveraFeature.prescriptions: FeatureEntitlement(
      feature: AveraFeature.prescriptions,
      key: 'prescriptions.basic',
      label: 'Prescriptions',
      category: 'Medical Files',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'Create and review prescriptions safely.',
    ),
    AveraFeature.reports: FeatureEntitlement(
      feature: AveraFeature.reports,
      key: 'reports.basic',
      label: 'Basic reports',
      category: 'Reporting and analytics',
      minimumPlan: SubscriptionPlan.starter,
      reason:
          'Review essential revenue, register, vaccination, inventory, and schedule reports.',
    ),
    AveraFeature.vera: FeatureEntitlement(
      feature: AveraFeature.vera,
      key: 'vera.basic',
      label: 'Vera Basic',
      category: 'Vera AI',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'General veterinary information without patient-record analysis.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.hospitalization: FeatureEntitlement(
      feature: AveraFeature.hospitalization,
      key: 'hospitalization.enabled',
      label: 'Hospitalization management',
      category: 'Hospitalization',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Coordinate inpatient wards, treatment plans, and discharge.',
    ),
    AveraFeature.treatmentBoard: FeatureEntitlement(
      feature: AveraFeature.treatmentBoard,
      key: 'treatment_board.enabled',
      label: 'Treatment Board',
      category: 'Hospitalization',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Coordinate scheduled inpatient treatments.',
    ),
    AveraFeature.surgery: FeatureEntitlement(
      feature: AveraFeature.surgery,
      key: 'surgery.enabled',
      label: 'Surgery management',
      category: 'Surgery',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Manage surgical preparation, theatre, recovery, and follow-up.',
    ),
    AveraFeature.imaging: FeatureEntitlement(
      feature: AveraFeature.imaging,
      key: 'imaging.enabled',
      label: 'Imaging',
      category: 'Imaging',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Coordinate diagnostic imaging records.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.advancedLaboratory: FeatureEntitlement(
      feature: AveraFeature.advancedLaboratory,
      key: 'laboratory.advanced',
      label: 'Advanced laboratory',
      category: 'Laboratory',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Use advanced laboratory records and interpretation workflows.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.advancedInventory: FeatureEntitlement(
      feature: AveraFeature.advancedInventory,
      key: 'inventory.advanced',
      label: 'Advanced inventory',
      category: 'Inventory',
      minimumPlan: SubscriptionPlan.professional,
      reason:
          'Use suppliers, batches, expiry tracking, and purchase workflows.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.multiLocationInventory: FeatureEntitlement(
      feature: AveraFeature.multiLocationInventory,
      key: 'inventory.multi_location',
      label: 'Multi-location inventory',
      category: 'Inventory',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Manage stock across clinic locations.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.clientPortal: FeatureEntitlement(
      feature: AveraFeature.clientPortal,
      key: 'client_portal.enabled',
      label: 'Client portal',
      category: 'Client communication',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Give owners a secure self-service portal.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.onlineBooking: FeatureEntitlement(
      feature: AveraFeature.onlineBooking,
      key: 'online_booking.enabled',
      label: 'Online booking',
      category: 'Client communication',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Accept online booking requests.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.emailReminders: FeatureEntitlement(
      feature: AveraFeature.emailReminders,
      key: 'reminders.email',
      label: 'Email reminders',
      category: 'Client communication',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Automate email reminders.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.smsReminders: FeatureEntitlement(
      feature: AveraFeature.smsReminders,
      key: 'reminders.sms',
      label: 'SMS reminders',
      category: 'Client communication',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Automate SMS reminders.',
      implementationStatus: FeatureImplementationStatus.planned,
    ),
    AveraFeature.whatsappReminders: FeatureEntitlement(
      feature: AveraFeature.whatsappReminders,
      key: 'reminders.whatsapp',
      label: 'WhatsApp reminders',
      category: 'Client communication',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Automate WhatsApp reminders.',
      implementationStatus: FeatureImplementationStatus.planned,
    ),
    AveraFeature.staffAnalytics: FeatureEntitlement(
      feature: AveraFeature.staffAnalytics,
      key: 'reports.advanced',
      label: 'Advanced reports and staff analytics',
      category: 'Reporting and analytics',
      minimumPlan: SubscriptionPlan.professional,
      reason: 'Review KPIs, clinical outcomes, and staff activity.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.veraClinical: FeatureEntitlement(
      feature: AveraFeature.veraClinical,
      key: 'vera.clinical',
      label: 'Vera Clinical Assistant',
      category: 'Vera AI',
      minimumPlan: SubscriptionPlan.professional,
      reason:
          'Patient-aware clinical decision support requiring veterinary review.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.corporateAnalytics: FeatureEntitlement(
      feature: AveraFeature.corporateAnalytics,
      key: 'reports.enterprise',
      label: 'Cross-clinic analytics',
      category: 'Reporting and analytics',
      minimumPlan: SubscriptionPlan.enterprise,
      reason: 'Compare performance across branches and clinic groups.',
      implementationStatus: FeatureImplementationStatus.planned,
    ),
    AveraFeature.centralInventory: FeatureEntitlement(
      feature: AveraFeature.centralInventory,
      key: 'inventory.central',
      label: 'Central inventory',
      category: 'Inventory',
      minimumPlan: SubscriptionPlan.enterprise,
      reason: 'Coordinate central stock, procurement, and warehouse workflows.',
      implementationStatus: FeatureImplementationStatus.planned,
    ),
    AveraFeature.corporateDashboard: FeatureEntitlement(
      feature: AveraFeature.corporateDashboard,
      key: 'corporate.dashboard',
      label: 'Corporate dashboard',
      category: 'Reporting and analytics',
      minimumPlan: SubscriptionPlan.enterprise,
      reason: 'View organisation-wide operations and financial performance.',
      implementationStatus: FeatureImplementationStatus.planned,
    ),
    AveraFeature.auditCentre: FeatureEntitlement(
      feature: AveraFeature.auditCentre,
      key: 'audit.centre',
      label: 'Audit Centre',
      category: 'Security',
      minimumPlan: SubscriptionPlan.enterprise,
      reason: 'Review enterprise audit and compliance activity.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.advancedPermissionBuilder: FeatureEntitlement(
      feature: AveraFeature.advancedPermissionBuilder,
      key: 'permissions.advanced',
      label: 'Advanced permission builder',
      category: 'Staff and permissions',
      minimumPlan: SubscriptionPlan.enterprise,
      reason: 'Create advanced enterprise role and approval policies.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.automation: FeatureEntitlement(
      feature: AveraFeature.automation,
      key: 'automation.unlimited',
      label: 'Workflow automation',
      category: 'Automation',
      minimumPlan: SubscriptionPlan.enterprise,
      reason: 'Create unlimited rule-based workflow automations.',
      implementationStatus: FeatureImplementationStatus.planned,
    ),
    AveraFeature.veraBasic: FeatureEntitlement(
      feature: AveraFeature.veraBasic,
      key: 'vera.basic.general',
      label: 'Vera Basic assistance',
      category: 'Vera AI',
      minimumPlan: SubscriptionPlan.starter,
      reason: 'General veterinary information without patient context.',
      implementationStatus: FeatureImplementationStatus.comingSoon,
    ),
    AveraFeature.veraEnterprise: FeatureEntitlement(
      feature: AveraFeature.veraEnterprise,
      key: 'vera.enterprise',
      label: 'Vera Intelligence Platform',
      category: 'Vera AI',
      minimumPlan: SubscriptionPlan.enterprise,
      reason:
          'Organisation-wide clinical, operational, and predictive intelligence.',
      implementationStatus: FeatureImplementationStatus.planned,
    ),
  };

  static FeatureEntitlement entitlement(AveraFeature feature) =>
      _entitlements[feature]!;

  static SubscriptionPlanDefinition plan(SubscriptionPlan plan) =>
      planDefinitions[plan]!;

  static FeatureAccessResult evaluate({
    required String subscriptionPlan,
    required AveraFeature feature,
    bool hasPermission = true,
    String subscriptionStatus = 'active',
    int? usage,
    int? limit,
    bool? overrideEnabled,
  }) {
    final currentPlan = SubscriptionPlan.fromStorage(subscriptionPlan);
    final detail = entitlement(feature);
    final status = SubscriptionStatus.fromStorage(subscriptionStatus);
    if (!hasPermission) {
      return _denied(
        FeatureAccessReason.permissionDenied,
        detail,
        currentPlan,
        status,
        usage,
        limit,
      );
    }
    if (status == SubscriptionStatus.suspended ||
        status == SubscriptionStatus.cancelled) {
      return _denied(
        FeatureAccessReason.subscriptionSuspended,
        detail,
        currentPlan,
        status,
        usage,
        limit,
      );
    }
    if (status == SubscriptionStatus.expired) {
      return _denied(
        FeatureAccessReason.subscriptionExpired,
        detail,
        currentPlan,
        status,
        usage,
        limit,
      );
    }
    final planAllows = currentPlan.index >= detail.minimumPlan.index;
    if (overrideEnabled == false || (!planAllows && overrideEnabled != true)) {
      return _denied(
        FeatureAccessReason.featureNotInPlan,
        detail,
        currentPlan,
        status,
        usage,
        limit,
      );
    }
    if (limit != null && usage != null && usage >= limit) {
      return _denied(
        FeatureAccessReason.usageLimitReached,
        detail,
        currentPlan,
        status,
        usage,
        limit,
      );
    }
    return FeatureAccessResult(
      allowed: true,
      reason:
          detail.implementationStatus ==
                  FeatureImplementationStatus.available ||
              detail.implementationStatus == FeatureImplementationStatus.limited
          ? FeatureAccessReason.allowed
          : FeatureAccessReason.featureComingSoon,
      entitlement: detail,
      currentPlan: currentPlan,
      requiredPlan: detail.minimumPlan,
      subscriptionStatus: status,
      implementationStatus: detail.implementationStatus,
      usage: usage,
      limit: limit,
    );
  }

  static FeatureAccessResult _denied(
    FeatureAccessReason reason,
    FeatureEntitlement detail,
    SubscriptionPlan currentPlan,
    SubscriptionStatus status,
    int? usage,
    int? limit,
  ) => FeatureAccessResult(
    allowed: false,
    reason: reason,
    entitlement: detail,
    currentPlan: currentPlan,
    requiredPlan: detail.minimumPlan,
    subscriptionStatus: status,
    implementationStatus: detail.implementationStatus,
    usage: usage,
    limit: limit,
  );

  static bool canAccess({
    required String subscriptionPlan,
    required AveraFeature feature,
  }) => evaluate(subscriptionPlan: subscriptionPlan, feature: feature).allowed;

  static void requireAccess({
    required String subscriptionPlan,
    required AveraFeature feature,
  }) {
    final result = evaluate(
      subscriptionPlan: subscriptionPlan,
      feature: feature,
    );
    if (!result.allowed) throw FeatureAccessDenied(result);
  }

  static List<FeatureEntitlement> get all => _entitlements.values.toList();

  static List<FeatureEntitlement> featuresFor(SubscriptionPlan plan) =>
      all.where((feature) => feature.minimumPlan.index <= plan.index).toList();
}
