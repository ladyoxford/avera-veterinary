String normalizeInventoryCatalogueSearch(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _compactInventoryCatalogueSearch(String value) =>
    normalizeInventoryCatalogueSearch(value).replaceAll(' ', '');

class InventorySubcategoryDefinition {
  const InventorySubcategoryDefinition({
    required this.id,
    required this.categoryId,
    required this.name,
    this.aliases = const [],
  });

  final String id;
  final String categoryId;
  final String name;
  final List<String> aliases;

  String get searchableText =>
      normalizeInventoryCatalogueSearch('$name ${aliases.join(' ')}');

  bool matches(String query) {
    final normalized = normalizeInventoryCatalogueSearch(query);
    return normalized.isEmpty ||
        searchableText.contains(normalized) ||
        _compactInventoryCatalogueSearch(
          searchableText,
        ).contains(_compactInventoryCatalogueSearch(query));
  }
}

class InventoryCategoryDefinition {
  const InventoryCategoryDefinition({
    required this.id,
    required this.name,
    required this.isSellable,
    this.aliases = const [],
    this.legacyIds = const [],
    this.isClinical = false,
    this.isPharmacy = false,
    this.isLaboratory = false,
    this.subcategories = const [],
  });

  final String id;
  final String name;
  final bool isSellable;
  final List<String> aliases;
  final List<String> legacyIds;
  final bool isClinical;
  final bool isPharmacy;
  final bool isLaboratory;
  final List<InventorySubcategoryDefinition> subcategories;

  String get searchableText => normalizeInventoryCatalogueSearch(
    '$name ${aliases.join(' ')} ${legacyIds.join(' ')}',
  );

  bool matches(String query) {
    final normalized = normalizeInventoryCatalogueSearch(query);
    return normalized.isEmpty ||
        searchableText.contains(normalized) ||
        _compactInventoryCatalogueSearch(
          searchableText,
        ).contains(_compactInventoryCatalogueSearch(query));
  }
}

enum InventoryStatusFilter {
  all,
  lowStock,
  expiring,
  expired;

  bool matches({
    required int quantity,
    required int minimumQuantity,
    required DateTime? expiryDate,
    required DateTime now,
  }) => switch (this) {
    InventoryStatusFilter.all => true,
    InventoryStatusFilter.lowStock => quantity <= minimumQuantity,
    InventoryStatusFilter.expiring =>
      expiryDate != null &&
          !expiryDate.isBefore(now) &&
          !expiryDate.isAfter(now.add(const Duration(days: 90))),
    InventoryStatusFilter.expired =>
      expiryDate != null && expiryDate.isBefore(now),
  };

  String get label => switch (this) {
    InventoryStatusFilter.all => 'Items',
    InventoryStatusFilter.lowStock => 'Low stock',
    InventoryStatusFilter.expiring => 'Expiring',
    InventoryStatusFilter.expired => 'Expired',
  };
}

class InventoryCategories {
  const InventoryCategories._();

  static const customCategoryId = 'other';
  static const customSubcategoryId = 'custom';
  static const unspecifiedSubcategoryId = 'not_specified';

  static const all = <InventoryCategoryDefinition>[
    InventoryCategoryDefinition(
      id: 'drugs',
      name: 'Medicines / Drugs',
      aliases: ['medicine', 'medication', 'pharmaceutical', 'pharmacy'],
      legacyIds: ['drug', 'medicines', 'medication', 'pharmaceuticals'],
      isSellable: true,
      isClinical: true,
      isPharmacy: true,
      subcategories: _drugSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'vaccines',
      name: 'Vaccines & Biologicals',
      aliases: ['vaccine', 'biologic', 'biologics', 'immunization'],
      legacyIds: ['biologics'],
      isSellable: true,
      isClinical: true,
      isPharmacy: true,
      subcategories: _vaccineSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'fluids_electrolytes',
      name: 'Fluids & Electrolytes',
      aliases: ['fluid therapy', 'iv fluids', 'rehydration'],
      legacyIds: ['fluids', 'fluid therapy'],
      isSellable: true,
      isClinical: true,
      isPharmacy: true,
      subcategories: _fluidSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'supplements',
      name: 'Vitamins, Minerals & Supplements',
      aliases: ['vitamins', 'minerals', 'nutraceuticals'],
      legacyIds: ['vitamin', 'supplement'],
      isSellable: true,
      isClinical: true,
      isPharmacy: true,
      subcategories: _supplementSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'nutrition_feed',
      name: 'Nutrition & Feed',
      aliases: ['nutrition', 'feed', 'animal food', 'pet food'],
      legacyIds: ['feed', 'pet_food', 'food'],
      isSellable: true,
      subcategories: _feedSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'diagnostic_laboratory',
      name: 'Diagnostic & Laboratory',
      aliases: ['diagnostics', 'laboratory', 'lab', 'testing'],
      legacyIds: [
        'laboratory_reagents',
        'diagnostic_test_kits',
        'laboratory_consumables',
      ],
      isSellable: true,
      isLaboratory: true,
      subcategories: _diagnosticSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'clinical_consumables',
      name: 'Clinical Consumables',
      aliases: ['consumables', 'clinical supplies'],
      isSellable: true,
      isClinical: true,
      subcategories: _clinicalSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'surgical_supplies',
      name: 'Surgical & Procedure Supplies',
      aliases: ['surgery', 'surgical supplies', 'procedure supplies'],
      isSellable: true,
      isClinical: true,
      subcategories: _surgicalSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'wound_care',
      name: 'Wound Care & Bandaging',
      aliases: ['wound care', 'bandages', 'dressings'],
      isSellable: true,
      isClinical: true,
      subcategories: _woundSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'infection_control',
      name: 'Infection Control & Disinfection',
      aliases: ['disinfectants', 'antiseptics', 'biosecurity'],
      isSellable: true,
      subcategories: _infectionControlSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'ppe_staff_safety',
      name: 'PPE & Staff Safety',
      aliases: ['ppe', 'personal protective equipment', 'staff safety'],
      isSellable: true,
      subcategories: _ppeSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'medical_equipment',
      name: 'Medical Equipment & Instruments',
      aliases: ['equipment', 'instruments', 'medical devices'],
      legacyIds: ['laboratory_equipment', 'general_equipment'],
      isSellable: false,
      isClinical: true,
      isLaboratory: true,
      subcategories: _equipmentSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'dental_care',
      name: 'Dental Care',
      aliases: ['dental', 'oral care'],
      isSellable: true,
      isClinical: true,
      subcategories: _dentalSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'grooming_dermatological',
      name: 'Grooming & Dermatological Care',
      aliases: ['grooming', 'dermatology', 'skin care'],
      legacyIds: ['grooming_supplies'],
      isSellable: true,
      subcategories: _groomingSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'reproduction_obstetrics',
      name: 'Reproduction, Breeding & Obstetrics',
      aliases: ['reproduction', 'breeding', 'obstetrics'],
      isSellable: true,
      isClinical: true,
      subcategories: _reproductionSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'farm_livestock',
      name: 'Farm & Livestock Supplies',
      aliases: ['farm supplies', 'livestock', 'ranch supplies'],
      isSellable: true,
      subcategories: _farmSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'poultry_supplies',
      name: 'Poultry Supplies',
      aliases: ['poultry', 'chicken supplies'],
      isSellable: true,
      subcategories: _poultrySubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'pet_accessories',
      name: 'Pet Accessories & Retail',
      aliases: ['pet accessories', 'accessories', 'pet shop', 'retail'],
      legacyIds: ['pet_accessory'],
      isSellable: true,
      subcategories: _petAccessorySubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'housing_handling',
      name: 'Animal Housing & Handling',
      aliases: ['housing', 'restraint', 'animal handling'],
      isSellable: true,
      subcategories: _housingSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'emergency_supplies',
      name: 'Emergency & Critical Care Supplies',
      aliases: ['emergency', 'critical care', 'resuscitation'],
      isSellable: true,
      isClinical: true,
      subcategories: _emergencySubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'pharmacy_supplies',
      name: 'Pharmacy & Dispensing Supplies',
      aliases: ['dispensing', 'pharmacy supplies'],
      isSellable: true,
      isPharmacy: true,
      subcategories: _pharmacySubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'cleaning_facility',
      name: 'Cleaning & Facility Supplies',
      aliases: ['cleaning', 'facility', 'janitorial'],
      isSellable: true,
      subcategories: _cleaningSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'office_admin',
      name: 'Office & Administrative Supplies',
      aliases: ['office', 'administrative', 'stationery'],
      legacyIds: ['office_supplies'],
      isSellable: false,
      subcategories: _officeSubcategories,
    ),
    InventoryCategoryDefinition(
      id: 'other',
      name: 'Other',
      aliases: ['custom', 'miscellaneous'],
      isSellable: false,
      subcategories: [
        InventorySubcategoryDefinition(
          id: 'other',
          categoryId: 'other',
          name: 'Other',
          aliases: ['miscellaneous'],
        ),
      ],
    ),
  ];

  static const _drugSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'antibiotics',
      categoryId: 'drugs',
      name: 'Antibiotics / Antibacterials',
      aliases: ['antibiotic', 'antibacterial', 'antimicrobial'],
    ),
    InventorySubcategoryDefinition(
      id: 'antifungals',
      categoryId: 'drugs',
      name: 'Antifungals',
      aliases: ['antifungal'],
    ),
    InventorySubcategoryDefinition(
      id: 'antivirals',
      categoryId: 'drugs',
      name: 'Antivirals',
      aliases: ['antiviral'],
    ),
    InventorySubcategoryDefinition(
      id: 'antiprotozoals',
      categoryId: 'drugs',
      name: 'Antiprotozoals',
      aliases: ['antiprotozoal'],
    ),
    InventorySubcategoryDefinition(
      id: 'anticoccidials',
      categoryId: 'drugs',
      name: 'Anticoccidials',
      aliases: ['coccidiostat', 'coccidiocide', 'coccidiosis medicine'],
    ),
    InventorySubcategoryDefinition(
      id: 'anthelmintics',
      categoryId: 'drugs',
      name: 'Anthelmintics / Dewormers',
      aliases: [
        'dewormer',
        'dewormers',
        'worm medicine',
        'wormer',
        'antihelminthic',
      ],
    ),
    InventorySubcategoryDefinition(
      id: 'ectoparasiticides',
      categoryId: 'drugs',
      name: 'Ectoparasiticides',
      aliases: [
        'tick medicine',
        'flea medicine',
        'acaricide',
        'miticide',
        'lice treatment',
        'tick',
        'tick and flea',
      ],
    ),
    InventorySubcategoryDefinition(
      id: 'endoparasiticides',
      categoryId: 'drugs',
      name: 'Endoparasiticides',
      aliases: ['internal parasites'],
    ),
    InventorySubcategoryDefinition(
      id: 'endectocides',
      categoryId: 'drugs',
      name: 'Endectocides',
      aliases: ['endo ectoparasiticides'],
    ),
    InventorySubcategoryDefinition(
      id: 'insecticides_repellents',
      categoryId: 'drugs',
      name: 'Insecticides & Repellents',
      aliases: ['insecticide', 'repellent'],
    ),
    InventorySubcategoryDefinition(
      id: 'nsaids',
      categoryId: 'drugs',
      name: 'NSAIDs / Anti-inflammatory',
      aliases: [
        'nsaid',
        'anti inflammatory',
        'anti-inflammatory',
        'painkiller',
        'pain killer',
        'antipyretic',
        'antipyrexic',
        'fever reducer',
        'analgesic',
      ],
    ),
    InventorySubcategoryDefinition(
      id: 'corticosteroids',
      categoryId: 'drugs',
      name: 'Corticosteroids',
      aliases: ['steroid'],
    ),
    InventorySubcategoryDefinition(
      id: 'analgesics',
      categoryId: 'drugs',
      name: 'Analgesics',
      aliases: ['pain relief'],
    ),
    InventorySubcategoryDefinition(
      id: 'antipyretics',
      categoryId: 'drugs',
      name: 'Antipyretics',
      aliases: ['fever reducer', 'antipyrexic'],
    ),
    InventorySubcategoryDefinition(
      id: 'local_anaesthetics',
      categoryId: 'drugs',
      name: 'Local Anaesthetics',
      aliases: ['local anesthetics', 'local anesthesia'],
    ),
    InventorySubcategoryDefinition(
      id: 'general_anaesthetics',
      categoryId: 'drugs',
      name: 'General Anaesthetics',
      aliases: ['general anesthetics', 'general anesthesia'],
    ),
    InventorySubcategoryDefinition(
      id: 'sedatives',
      categoryId: 'drugs',
      name: 'Sedatives & Tranquilizers',
      aliases: ['tranquilizer', 'sedation'],
    ),
    InventorySubcategoryDefinition(
      id: 'muscle_relaxants',
      categoryId: 'drugs',
      name: 'Muscle Relaxants',
    ),
    InventorySubcategoryDefinition(
      id: 'anticonvulsants',
      categoryId: 'drugs',
      name: 'Anticonvulsants / Antiepileptics',
      aliases: ['antiepileptic', 'seizure medicine'],
    ),
    InventorySubcategoryDefinition(
      id: 'psychotropics',
      categoryId: 'drugs',
      name: 'Behavioural / Psychotropic Medicines',
      aliases: ['behavioral medicine', 'anxiolytic'],
    ),
    InventorySubcategoryDefinition(
      id: 'antihistamines',
      categoryId: 'drugs',
      name: 'Antihistamines / Anti-allergic',
      aliases: ['allergy medicine'],
    ),
    InventorySubcategoryDefinition(
      id: 'respiratory',
      categoryId: 'drugs',
      name: 'Respiratory Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'bronchodilators',
      categoryId: 'drugs',
      name: 'Bronchodilators',
    ),
    InventorySubcategoryDefinition(
      id: 'antitussives',
      categoryId: 'drugs',
      name: 'Antitussives',
      aliases: ['cough medicine'],
    ),
    InventorySubcategoryDefinition(
      id: 'expectorants',
      categoryId: 'drugs',
      name: 'Expectorants / Mucolytics',
      aliases: ['mucolytic'],
    ),
    InventorySubcategoryDefinition(
      id: 'cardiovascular',
      categoryId: 'drugs',
      name: 'Cardiovascular Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'antiarrhythmics',
      categoryId: 'drugs',
      name: 'Antiarrhythmics',
    ),
    InventorySubcategoryDefinition(
      id: 'antihypertensives',
      categoryId: 'drugs',
      name: 'Antihypertensives',
    ),
    InventorySubcategoryDefinition(
      id: 'vasopressors_inotropes',
      categoryId: 'drugs',
      name: 'Vasopressors / Inotropes',
      aliases: ['inotrope'],
    ),
    InventorySubcategoryDefinition(
      id: 'diuretics',
      categoryId: 'drugs',
      name: 'Diuretics',
    ),
    InventorySubcategoryDefinition(
      id: 'gastrointestinal',
      categoryId: 'drugs',
      name: 'Gastrointestinal Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'antiemetics',
      categoryId: 'drugs',
      name: 'Antiemetics',
    ),
    InventorySubcategoryDefinition(
      id: 'antidiarrheals',
      categoryId: 'drugs',
      name: 'Antidiarrheals',
    ),
    InventorySubcategoryDefinition(
      id: 'laxatives',
      categoryId: 'drugs',
      name: 'Laxatives',
    ),
    InventorySubcategoryDefinition(
      id: 'gastroprotectants',
      categoryId: 'drugs',
      name: 'Gastroprotectants',
    ),
    InventorySubcategoryDefinition(
      id: 'antacids',
      categoryId: 'drugs',
      name: 'Antacids / Acid Suppressants',
    ),
    InventorySubcategoryDefinition(
      id: 'rumen_digestive',
      categoryId: 'drugs',
      name: 'Rumen / Digestive Support',
    ),
    InventorySubcategoryDefinition(
      id: 'hepatoprotective',
      categoryId: 'drugs',
      name: 'Hepatoprotective Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'renal_urinary',
      categoryId: 'drugs',
      name: 'Renal / Urinary Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'urogenital',
      categoryId: 'drugs',
      name: 'Urogenital Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'endocrine_hormonal',
      categoryId: 'drugs',
      name: 'Endocrine / Hormonal Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'thyroid',
      categoryId: 'drugs',
      name: 'Thyroid Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'diabetes_insulin',
      categoryId: 'drugs',
      name: 'Diabetes / Insulin',
    ),
    InventorySubcategoryDefinition(
      id: 'reproductive_hormones',
      categoryId: 'drugs',
      name: 'Reproductive Hormones',
    ),
    InventorySubcategoryDefinition(
      id: 'prostaglandins',
      categoryId: 'drugs',
      name: 'Prostaglandins',
    ),
    InventorySubcategoryDefinition(
      id: 'oxytocics',
      categoryId: 'drugs',
      name: 'Oxytocics',
    ),
    InventorySubcategoryDefinition(
      id: 'uterine_reproductive',
      categoryId: 'drugs',
      name: 'Uterine / Reproductive Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'dermatological',
      categoryId: 'drugs',
      name: 'Dermatological Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'otic',
      categoryId: 'drugs',
      name: 'Otic / Ear Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'ophthalmic',
      categoryId: 'drugs',
      name: 'Ophthalmic / Eye Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'hematologic',
      categoryId: 'drugs',
      name: 'Hematologic Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'hematinics',
      categoryId: 'drugs',
      name: 'Hematinics',
    ),
    InventorySubcategoryDefinition(
      id: 'anticoagulants',
      categoryId: 'drugs',
      name: 'Anticoagulants',
    ),
    InventorySubcategoryDefinition(
      id: 'hemostatics',
      categoryId: 'drugs',
      name: 'Hemostatics',
    ),
    InventorySubcategoryDefinition(
      id: 'immunomodulators',
      categoryId: 'drugs',
      name: 'Immunomodulators',
    ),
    InventorySubcategoryDefinition(
      id: 'immunosuppressants',
      categoryId: 'drugs',
      name: 'Immunosuppressants',
    ),
    InventorySubcategoryDefinition(
      id: 'antineoplastics',
      categoryId: 'drugs',
      name: 'Antineoplastic / Chemotherapy',
    ),
    InventorySubcategoryDefinition(
      id: 'antidotes_antitoxins',
      categoryId: 'drugs',
      name: 'Antidotes & Antitoxins',
    ),
    InventorySubcategoryDefinition(
      id: 'euthanasia',
      categoryId: 'drugs',
      name: 'Euthanasia Agents',
    ),
    InventorySubcategoryDefinition(
      id: 'topical',
      categoryId: 'drugs',
      name: 'Topical Medicines',
    ),
    InventorySubcategoryDefinition(
      id: 'medicated_premixes',
      categoryId: 'drugs',
      name: 'Medicated Premixes',
    ),
    InventorySubcategoryDefinition(
      id: 'other_medicines',
      categoryId: 'drugs',
      name: 'Other Veterinary Medicines',
    ),
  ];

  static const _vaccineSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'canine_vaccines',
      categoryId: 'vaccines',
      name: 'Canine Vaccines',
      aliases: ['dog vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'feline_vaccines',
      categoryId: 'vaccines',
      name: 'Feline Vaccines',
      aliases: ['cat vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'cattle_vaccines',
      categoryId: 'vaccines',
      name: 'Cattle Vaccines',
      aliases: ['bovine vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'sheep_vaccines',
      categoryId: 'vaccines',
      name: 'Sheep Vaccines',
      aliases: ['ovine vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'goat_vaccines',
      categoryId: 'vaccines',
      name: 'Goat Vaccines',
      aliases: ['caprine vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'pig_vaccines',
      categoryId: 'vaccines',
      name: 'Pig / Swine Vaccines',
      aliases: ['porcine vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'poultry_vaccines',
      categoryId: 'vaccines',
      name: 'Poultry Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'equine_vaccines',
      categoryId: 'vaccines',
      name: 'Equine Vaccines',
      aliases: ['horse vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'rabbit_vaccines',
      categoryId: 'vaccines',
      name: 'Rabbit Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'aquaculture_vaccines',
      categoryId: 'vaccines',
      name: 'Aquaculture Vaccines',
      aliases: ['fish vaccines'],
    ),
    InventorySubcategoryDefinition(
      id: 'multispecies_vaccines',
      categoryId: 'vaccines',
      name: 'Multispecies Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'bacterial_vaccines',
      categoryId: 'vaccines',
      name: 'Bacterial Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'viral_vaccines',
      categoryId: 'vaccines',
      name: 'Viral Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'protozoal_vaccines',
      categoryId: 'vaccines',
      name: 'Protozoal Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'combined_vaccines',
      categoryId: 'vaccines',
      name: 'Combined / Multivalent Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'autogenous_vaccines',
      categoryId: 'vaccines',
      name: 'Autogenous Vaccines',
    ),
    InventorySubcategoryDefinition(
      id: 'antisera',
      categoryId: 'vaccines',
      name: 'Antisera',
    ),
    InventorySubcategoryDefinition(
      id: 'antitoxins',
      categoryId: 'vaccines',
      name: 'Antitoxins',
    ),
    InventorySubcategoryDefinition(
      id: 'immunoglobulins',
      categoryId: 'vaccines',
      name: 'Immunoglobulins',
    ),
    InventorySubcategoryDefinition(
      id: 'diagnostic_biologicals',
      categoryId: 'vaccines',
      name: 'Diagnostic Biologicals',
    ),
    InventorySubcategoryDefinition(
      id: 'other_biologicals',
      categoryId: 'vaccines',
      name: 'Other Biologicals',
    ),
  ];

  static const _fluidSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'crystalloids',
      categoryId: 'fluids_electrolytes',
      name: 'Crystalloids',
    ),
    InventorySubcategoryDefinition(
      id: 'normal_saline',
      categoryId: 'fluids_electrolytes',
      name: 'Normal Saline',
    ),
    InventorySubcategoryDefinition(
      id: 'ringers_lactate',
      categoryId: 'fluids_electrolytes',
      name: "Ringer's Lactate / Hartmann's",
      aliases: ['hartmanns'],
    ),
    InventorySubcategoryDefinition(
      id: 'dextrose',
      categoryId: 'fluids_electrolytes',
      name: 'Dextrose Solutions',
    ),
    InventorySubcategoryDefinition(
      id: 'dextrose_saline',
      categoryId: 'fluids_electrolytes',
      name: 'Dextrose-Saline Solutions',
    ),
    InventorySubcategoryDefinition(
      id: 'maintenance_fluids',
      categoryId: 'fluids_electrolytes',
      name: 'Maintenance Fluids',
    ),
    InventorySubcategoryDefinition(
      id: 'hypertonic_saline',
      categoryId: 'fluids_electrolytes',
      name: 'Hypertonic Saline',
    ),
    InventorySubcategoryDefinition(
      id: 'electrolyte_solutions',
      categoryId: 'fluids_electrolytes',
      name: 'Electrolyte Solutions',
    ),
    InventorySubcategoryDefinition(
      id: 'oral_rehydration',
      categoryId: 'fluids_electrolytes',
      name: 'Oral Rehydration Solutions',
    ),
    InventorySubcategoryDefinition(
      id: 'calcium_solutions',
      categoryId: 'fluids_electrolytes',
      name: 'Calcium Solutions',
    ),
    InventorySubcategoryDefinition(
      id: 'magnesium_solutions',
      categoryId: 'fluids_electrolytes',
      name: 'Magnesium Solutions',
    ),
    InventorySubcategoryDefinition(
      id: 'potassium_supplements',
      categoryId: 'fluids_electrolytes',
      name: 'Potassium Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'bicarbonate_buffers',
      categoryId: 'fluids_electrolytes',
      name: 'Bicarbonate / Buffer Solutions',
    ),
    InventorySubcategoryDefinition(
      id: 'colloids',
      categoryId: 'fluids_electrolytes',
      name: 'Colloids',
    ),
    InventorySubcategoryDefinition(
      id: 'plasma_blood',
      categoryId: 'fluids_electrolytes',
      name: 'Plasma / Blood Products',
    ),
    InventorySubcategoryDefinition(
      id: 'fluid_additives',
      categoryId: 'fluids_electrolytes',
      name: 'Fluid Additives',
    ),
    InventorySubcategoryDefinition(
      id: 'other_fluids',
      categoryId: 'fluids_electrolytes',
      name: 'Other Fluid Therapy Products',
    ),
  ];

  static const _supplementSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'multivitamins',
      categoryId: 'supplements',
      name: 'Multivitamins',
    ),
    InventorySubcategoryDefinition(
      id: 'vitamin_a',
      categoryId: 'supplements',
      name: 'Vitamin A',
    ),
    InventorySubcategoryDefinition(
      id: 'vitamin_b',
      categoryId: 'supplements',
      name: 'Vitamin B Complex',
    ),
    InventorySubcategoryDefinition(
      id: 'vitamin_c',
      categoryId: 'supplements',
      name: 'Vitamin C',
    ),
    InventorySubcategoryDefinition(
      id: 'vitamin_d',
      categoryId: 'supplements',
      name: 'Vitamin D',
    ),
    InventorySubcategoryDefinition(
      id: 'vitamin_e',
      categoryId: 'supplements',
      name: 'Vitamin E',
    ),
    InventorySubcategoryDefinition(
      id: 'vitamin_k',
      categoryId: 'supplements',
      name: 'Vitamin K',
    ),
    InventorySubcategoryDefinition(
      id: 'iron',
      categoryId: 'supplements',
      name: 'Iron Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'calcium',
      categoryId: 'supplements',
      name: 'Calcium Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'phosphorus',
      categoryId: 'supplements',
      name: 'Phosphorus Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'magnesium',
      categoryId: 'supplements',
      name: 'Magnesium Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'trace_minerals',
      categoryId: 'supplements',
      name: 'Trace Minerals',
    ),
    InventorySubcategoryDefinition(
      id: 'mineral_premixes',
      categoryId: 'supplements',
      name: 'Mineral Premixes',
    ),
    InventorySubcategoryDefinition(
      id: 'electrolyte_supplements',
      categoryId: 'supplements',
      name: 'Electrolyte Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'amino_acids',
      categoryId: 'supplements',
      name: 'Amino Acid Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'probiotics',
      categoryId: 'supplements',
      name: 'Probiotics',
    ),
    InventorySubcategoryDefinition(
      id: 'prebiotics',
      categoryId: 'supplements',
      name: 'Prebiotics',
    ),
    InventorySubcategoryDefinition(
      id: 'digestive_supplements',
      categoryId: 'supplements',
      name: 'Digestive Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'joint_supplements',
      categoryId: 'supplements',
      name: 'Joint Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'skin_coat_supplements',
      categoryId: 'supplements',
      name: 'Skin & Coat Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'liver_supplements',
      categoryId: 'supplements',
      name: 'Liver Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'renal_supplements',
      categoryId: 'supplements',
      name: 'Renal Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'immune_support',
      categoryId: 'supplements',
      name: 'Immune Support',
    ),
    InventorySubcategoryDefinition(
      id: 'energy_supplements',
      categoryId: 'supplements',
      name: 'Energy Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'appetite_support',
      categoryId: 'supplements',
      name: 'Appetite Support',
    ),
    InventorySubcategoryDefinition(
      id: 'reproductive_supplements',
      categoryId: 'supplements',
      name: 'Reproductive Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'other_supplements',
      categoryId: 'supplements',
      name: 'Other Supplements',
    ),
  ];

  static const _feedSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'dog_food',
      categoryId: 'nutrition_feed',
      name: 'Dog Food',
    ),
    InventorySubcategoryDefinition(
      id: 'cat_food',
      categoryId: 'nutrition_feed',
      name: 'Cat Food',
    ),
    InventorySubcategoryDefinition(
      id: 'puppy_food',
      categoryId: 'nutrition_feed',
      name: 'Puppy Food',
    ),
    InventorySubcategoryDefinition(
      id: 'kitten_food',
      categoryId: 'nutrition_feed',
      name: 'Kitten Food',
    ),
    InventorySubcategoryDefinition(
      id: 'therapeutic_diets',
      categoryId: 'nutrition_feed',
      name: 'Prescription / Therapeutic Diets',
    ),
    InventorySubcategoryDefinition(
      id: 'recovery_diets',
      categoryId: 'nutrition_feed',
      name: 'Recovery Diets',
    ),
    InventorySubcategoryDefinition(
      id: 'cattle_feed',
      categoryId: 'nutrition_feed',
      name: 'Cattle Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'sheep_feed',
      categoryId: 'nutrition_feed',
      name: 'Sheep Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'goat_feed',
      categoryId: 'nutrition_feed',
      name: 'Goat Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'pig_feed',
      categoryId: 'nutrition_feed',
      name: 'Pig Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'poultry_feed',
      categoryId: 'nutrition_feed',
      name: 'Poultry Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'horse_feed',
      categoryId: 'nutrition_feed',
      name: 'Horse Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'rabbit_feed',
      categoryId: 'nutrition_feed',
      name: 'Rabbit Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'fish_feed',
      categoryId: 'nutrition_feed',
      name: 'Fish / Aquaculture Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'milk_replacers',
      categoryId: 'nutrition_feed',
      name: 'Milk Replacers',
    ),
    InventorySubcategoryDefinition(
      id: 'calf_starter',
      categoryId: 'nutrition_feed',
      name: 'Calf Starter',
    ),
    InventorySubcategoryDefinition(
      id: 'young_animal_feed',
      categoryId: 'nutrition_feed',
      name: 'Young Animal Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'concentrates',
      categoryId: 'nutrition_feed',
      name: 'Concentrates',
    ),
    InventorySubcategoryDefinition(
      id: 'roughage_forage',
      categoryId: 'nutrition_feed',
      name: 'Roughage / Forage Products',
    ),
    InventorySubcategoryDefinition(
      id: 'feed_premixes',
      categoryId: 'nutrition_feed',
      name: 'Feed Premixes',
    ),
    InventorySubcategoryDefinition(
      id: 'protein_supplements',
      categoryId: 'nutrition_feed',
      name: 'Protein Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'energy_feed',
      categoryId: 'nutrition_feed',
      name: 'Energy Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'feed_additives',
      categoryId: 'nutrition_feed',
      name: 'Feed Additives',
    ),
    InventorySubcategoryDefinition(
      id: 'rumen_additives',
      categoryId: 'nutrition_feed',
      name: 'Yeast / Rumen Additives',
    ),
    InventorySubcategoryDefinition(
      id: 'feed_probiotics',
      categoryId: 'nutrition_feed',
      name: 'Probiotics',
    ),
    InventorySubcategoryDefinition(
      id: 'mycotoxin_binders',
      categoryId: 'nutrition_feed',
      name: 'Mycotoxin Binders',
    ),
    InventorySubcategoryDefinition(
      id: 'medicated_feed',
      categoryId: 'nutrition_feed',
      name: 'Medicated Feed',
    ),
    InventorySubcategoryDefinition(
      id: 'treats',
      categoryId: 'nutrition_feed',
      name: 'Treats',
    ),
    InventorySubcategoryDefinition(
      id: 'other_feed',
      categoryId: 'nutrition_feed',
      name: 'Other Feed & Nutrition',
    ),
  ];

  static const _diagnosticSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'rapid_tests',
      categoryId: 'diagnostic_laboratory',
      name: 'Rapid Test Kits',
    ),
    InventorySubcategoryDefinition(
      id: 'serology',
      categoryId: 'diagnostic_laboratory',
      name: 'Serology Kits',
    ),
    InventorySubcategoryDefinition(
      id: 'antigen_tests',
      categoryId: 'diagnostic_laboratory',
      name: 'Antigen Tests',
    ),
    InventorySubcategoryDefinition(
      id: 'antibody_tests',
      categoryId: 'diagnostic_laboratory',
      name: 'Antibody Tests',
    ),
    InventorySubcategoryDefinition(
      id: 'pregnancy_tests',
      categoryId: 'diagnostic_laboratory',
      name: 'Pregnancy Tests',
    ),
    InventorySubcategoryDefinition(
      id: 'blood_collection',
      categoryId: 'diagnostic_laboratory',
      name: 'Blood Collection Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'urinalysis',
      categoryId: 'diagnostic_laboratory',
      name: 'Urinalysis',
    ),
    InventorySubcategoryDefinition(
      id: 'faecal_testing',
      categoryId: 'diagnostic_laboratory',
      name: 'Faecal / Fecal Testing',
    ),
    InventorySubcategoryDefinition(
      id: 'parasitology',
      categoryId: 'diagnostic_laboratory',
      name: 'Parasitology',
    ),
    InventorySubcategoryDefinition(
      id: 'microbiology',
      categoryId: 'diagnostic_laboratory',
      name: 'Microbiology',
    ),
    InventorySubcategoryDefinition(
      id: 'culture_sensitivity',
      categoryId: 'diagnostic_laboratory',
      name: 'Culture & Sensitivity',
    ),
    InventorySubcategoryDefinition(
      id: 'cytology',
      categoryId: 'diagnostic_laboratory',
      name: 'Cytology',
    ),
    InventorySubcategoryDefinition(
      id: 'histopathology',
      categoryId: 'diagnostic_laboratory',
      name: 'Histopathology Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'biopsy',
      categoryId: 'diagnostic_laboratory',
      name: 'Biopsy Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'hematology_reagents',
      categoryId: 'diagnostic_laboratory',
      name: 'Hematology Reagents',
    ),
    InventorySubcategoryDefinition(
      id: 'biochemistry_reagents',
      categoryId: 'diagnostic_laboratory',
      name: 'Biochemistry Reagents',
    ),
    InventorySubcategoryDefinition(
      id: 'microscopy',
      categoryId: 'diagnostic_laboratory',
      name: 'Microscopy Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'slides_cover_slips',
      categoryId: 'diagnostic_laboratory',
      name: 'Microscope Slides & Cover Slips',
    ),
    InventorySubcategoryDefinition(
      id: 'stains',
      categoryId: 'diagnostic_laboratory',
      name: 'Stains',
    ),
    InventorySubcategoryDefinition(
      id: 'sample_containers',
      categoryId: 'diagnostic_laboratory',
      name: 'Sample Containers',
    ),
    InventorySubcategoryDefinition(
      id: 'swabs_transport',
      categoryId: 'diagnostic_laboratory',
      name: 'Swabs & Transport Media',
    ),
    InventorySubcategoryDefinition(
      id: 'pcr_molecular',
      categoryId: 'diagnostic_laboratory',
      name: 'PCR / Molecular Diagnostics',
    ),
    InventorySubcategoryDefinition(
      id: 'blood_glucose',
      categoryId: 'diagnostic_laboratory',
      name: 'Blood Glucose Testing',
    ),
    InventorySubcategoryDefinition(
      id: 'ketone_testing',
      categoryId: 'diagnostic_laboratory',
      name: 'Ketone Testing',
    ),
    InventorySubcategoryDefinition(
      id: 'diagnostic_strips',
      categoryId: 'diagnostic_laboratory',
      name: 'Diagnostic Strips',
    ),
    InventorySubcategoryDefinition(
      id: 'laboratory_reagents',
      categoryId: 'diagnostic_laboratory',
      name: 'Laboratory Reagents',
    ),
    InventorySubcategoryDefinition(
      id: 'laboratory_consumables',
      categoryId: 'diagnostic_laboratory',
      name: 'Laboratory Consumables',
    ),
    InventorySubcategoryDefinition(
      id: 'other_diagnostics',
      categoryId: 'diagnostic_laboratory',
      name: 'Other Diagnostics',
    ),
  ];

  static const _clinicalSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'syringes',
      categoryId: 'clinical_consumables',
      name: 'Syringes',
    ),
    InventorySubcategoryDefinition(
      id: 'needles',
      categoryId: 'clinical_consumables',
      name: 'Hypodermic Needles',
    ),
    InventorySubcategoryDefinition(
      id: 'iv_catheters',
      categoryId: 'clinical_consumables',
      name: 'IV Catheters',
    ),
    InventorySubcategoryDefinition(
      id: 'butterfly_needles',
      categoryId: 'clinical_consumables',
      name: 'Butterfly Needles',
    ),
    InventorySubcategoryDefinition(
      id: 'infusion_sets',
      categoryId: 'clinical_consumables',
      name: 'Infusion Sets / Giving Sets',
    ),
    InventorySubcategoryDefinition(
      id: 'extension_lines',
      categoryId: 'clinical_consumables',
      name: 'Extension Lines & Three-Way Taps',
    ),
    InventorySubcategoryDefinition(
      id: 'feeding_tubes',
      categoryId: 'clinical_consumables',
      name: 'Feeding Tubes',
    ),
    InventorySubcategoryDefinition(
      id: 'urinary_catheters',
      categoryId: 'clinical_consumables',
      name: 'Urinary Catheters',
    ),
    InventorySubcategoryDefinition(
      id: 'endotracheal_tubes',
      categoryId: 'clinical_consumables',
      name: 'Endotracheal Tubes',
    ),
    InventorySubcategoryDefinition(
      id: 'nasogastric_tubes',
      categoryId: 'clinical_consumables',
      name: 'Nasogastric Tubes',
    ),
    InventorySubcategoryDefinition(
      id: 'collection_tubes',
      categoryId: 'clinical_consumables',
      name: 'Collection Tubes & Specimen Containers',
    ),
    InventorySubcategoryDefinition(
      id: 'cotton_gauze',
      categoryId: 'clinical_consumables',
      name: 'Cotton Wool & Gauze',
    ),
    InventorySubcategoryDefinition(
      id: 'applicators',
      categoryId: 'clinical_consumables',
      name: 'Applicators',
    ),
    InventorySubcategoryDefinition(
      id: 'lubricants',
      categoryId: 'clinical_consumables',
      name: 'Lubricants',
    ),
    InventorySubcategoryDefinition(
      id: 'disposable_clinical',
      categoryId: 'clinical_consumables',
      name: 'Disposable Clinical Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'other_consumables',
      categoryId: 'clinical_consumables',
      name: 'Other Consumables',
    ),
  ];

  static const _surgicalSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'sutures',
      categoryId: 'surgical_supplies',
      name: 'Sutures',
    ),
    InventorySubcategoryDefinition(
      id: 'suture_needles',
      categoryId: 'surgical_supplies',
      name: 'Suture Needles',
    ),
    InventorySubcategoryDefinition(
      id: 'blades_scalpels',
      categoryId: 'surgical_supplies',
      name: 'Surgical Blades & Scalpels',
    ),
    InventorySubcategoryDefinition(
      id: 'surgical_drapes',
      categoryId: 'surgical_supplies',
      name: 'Surgical Drapes',
    ),
    InventorySubcategoryDefinition(
      id: 'surgical_gowns_gloves',
      categoryId: 'surgical_supplies',
      name: 'Surgical Gowns & Gloves',
    ),
    InventorySubcategoryDefinition(
      id: 'surgical_packs',
      categoryId: 'surgical_supplies',
      name: 'Surgical Packs',
    ),
    InventorySubcategoryDefinition(
      id: 'hemostatic_materials',
      categoryId: 'surgical_supplies',
      name: 'Hemostatic Materials',
    ),
    InventorySubcategoryDefinition(
      id: 'wound_closure',
      categoryId: 'surgical_supplies',
      name: 'Wound Closure Products',
    ),
    InventorySubcategoryDefinition(
      id: 'staplers',
      categoryId: 'surgical_supplies',
      name: 'Staplers & Staples',
    ),
    InventorySubcategoryDefinition(
      id: 'drains_tubing',
      categoryId: 'surgical_supplies',
      name: 'Drains & Surgical Tubing',
    ),
    InventorySubcategoryDefinition(
      id: 'orthopedic',
      categoryId: 'surgical_supplies',
      name: 'Orthopedic Supplies & Implants',
    ),
    InventorySubcategoryDefinition(
      id: 'casting',
      categoryId: 'surgical_supplies',
      name: 'Casting Materials',
    ),
    InventorySubcategoryDefinition(
      id: 'procedure_kits',
      categoryId: 'surgical_supplies',
      name: 'Procedure Kits',
    ),
    InventorySubcategoryDefinition(
      id: 'sterile_consumables',
      categoryId: 'surgical_supplies',
      name: 'Sterile Consumables',
    ),
    InventorySubcategoryDefinition(
      id: 'other_surgical',
      categoryId: 'surgical_supplies',
      name: 'Other Surgical Supplies',
    ),
  ];

  static const _woundSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'dressings',
      categoryId: 'wound_care',
      name: 'Dressings',
    ),
    InventorySubcategoryDefinition(
      id: 'absorbent_dressings',
      categoryId: 'wound_care',
      name: 'Absorbent Dressings',
    ),
    InventorySubcategoryDefinition(
      id: 'non_adherent_dressings',
      categoryId: 'wound_care',
      name: 'Non-Adherent Dressings',
    ),
    InventorySubcategoryDefinition(
      id: 'bandages',
      categoryId: 'wound_care',
      name: 'Bandages',
    ),
    InventorySubcategoryDefinition(
      id: 'elastic_bandages',
      categoryId: 'wound_care',
      name: 'Elastic Bandages',
    ),
    InventorySubcategoryDefinition(
      id: 'cohesive_bandages',
      categoryId: 'wound_care',
      name: 'Cohesive Bandages',
    ),
    InventorySubcategoryDefinition(
      id: 'adhesive_tape',
      categoryId: 'wound_care',
      name: 'Adhesive Tape',
    ),
    InventorySubcategoryDefinition(
      id: 'cotton_padding',
      categoryId: 'wound_care',
      name: 'Cotton Padding',
    ),
    InventorySubcategoryDefinition(
      id: 'splints',
      categoryId: 'wound_care',
      name: 'Splints',
    ),
    InventorySubcategoryDefinition(
      id: 'wound_cleansers',
      categoryId: 'wound_care',
      name: 'Wound Cleansers',
    ),
    InventorySubcategoryDefinition(
      id: 'topical_antiseptics',
      categoryId: 'wound_care',
      name: 'Topical Antiseptics',
    ),
    InventorySubcategoryDefinition(
      id: 'wound_sprays_ointments',
      categoryId: 'wound_care',
      name: 'Wound Sprays & Ointments',
    ),
    InventorySubcategoryDefinition(
      id: 'hemostatic_dressings',
      categoryId: 'wound_care',
      name: 'Hemostatic Dressings',
    ),
    InventorySubcategoryDefinition(
      id: 'burn_care',
      categoryId: 'wound_care',
      name: 'Burn Care',
    ),
    InventorySubcategoryDefinition(
      id: 'protective_collars',
      categoryId: 'wound_care',
      name: 'Protective Collars / E-Collars',
    ),
    InventorySubcategoryDefinition(
      id: 'other_wound_care',
      categoryId: 'wound_care',
      name: 'Other Wound Care',
    ),
  ];

  static const _infectionControlSubcategories =
      <InventorySubcategoryDefinition>[
        InventorySubcategoryDefinition(
          id: 'surface_disinfectants',
          categoryId: 'infection_control',
          name: 'Surface Disinfectants',
        ),
        InventorySubcategoryDefinition(
          id: 'instrument_disinfectants',
          categoryId: 'infection_control',
          name: 'Instrument Disinfectants',
        ),
        InventorySubcategoryDefinition(
          id: 'antiseptics',
          categoryId: 'infection_control',
          name: 'Antiseptics',
        ),
        InventorySubcategoryDefinition(
          id: 'hand_sanitizers',
          categoryId: 'infection_control',
          name: 'Hand Sanitizers',
        ),
        InventorySubcategoryDefinition(
          id: 'surgical_scrubs',
          categoryId: 'infection_control',
          name: 'Surgical Scrubs',
        ),
        InventorySubcategoryDefinition(
          id: 'chlorhexidine',
          categoryId: 'infection_control',
          name: 'Chlorhexidine Products',
        ),
        InventorySubcategoryDefinition(
          id: 'iodine',
          categoryId: 'infection_control',
          name: 'Iodine / Iodophors',
        ),
        InventorySubcategoryDefinition(
          id: 'alcohol_products',
          categoryId: 'infection_control',
          name: 'Alcohol-Based Products',
        ),
        InventorySubcategoryDefinition(
          id: 'farm_disinfectants',
          categoryId: 'infection_control',
          name: 'Farm Disinfectants',
        ),
        InventorySubcategoryDefinition(
          id: 'footbath_disinfectants',
          categoryId: 'infection_control',
          name: 'Footbath Disinfectants',
        ),
        InventorySubcategoryDefinition(
          id: 'kennel_disinfectants',
          categoryId: 'infection_control',
          name: 'Kennel Disinfectants',
        ),
        InventorySubcategoryDefinition(
          id: 'sterilization',
          categoryId: 'infection_control',
          name: 'Sterilization Products & Indicators',
        ),
        InventorySubcategoryDefinition(
          id: 'biosecurity',
          categoryId: 'infection_control',
          name: 'Biosecurity Products',
        ),
        InventorySubcategoryDefinition(
          id: 'waste_disinfection',
          categoryId: 'infection_control',
          name: 'Waste Disinfection',
        ),
        InventorySubcategoryDefinition(
          id: 'other_infection_control',
          categoryId: 'infection_control',
          name: 'Other Infection Control',
        ),
      ];

  static const _ppeSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'examination_gloves',
      categoryId: 'ppe_staff_safety',
      name: 'Examination Gloves',
    ),
    InventorySubcategoryDefinition(
      id: 'surgical_gloves',
      categoryId: 'ppe_staff_safety',
      name: 'Surgical Gloves',
    ),
    InventorySubcategoryDefinition(
      id: 'face_masks',
      categoryId: 'ppe_staff_safety',
      name: 'Face Masks',
    ),
    InventorySubcategoryDefinition(
      id: 'respirators',
      categoryId: 'ppe_staff_safety',
      name: 'Respirators',
    ),
    InventorySubcategoryDefinition(
      id: 'protective_gowns',
      categoryId: 'ppe_staff_safety',
      name: 'Protective Gowns & Aprons',
    ),
    InventorySubcategoryDefinition(
      id: 'coveralls',
      categoryId: 'ppe_staff_safety',
      name: 'Coveralls',
    ),
    InventorySubcategoryDefinition(
      id: 'boots_shoe_covers',
      categoryId: 'ppe_staff_safety',
      name: 'Boots / Shoe Covers',
    ),
    InventorySubcategoryDefinition(
      id: 'face_shields',
      categoryId: 'ppe_staff_safety',
      name: 'Face Shields',
    ),
    InventorySubcategoryDefinition(
      id: 'protective_eyewear',
      categoryId: 'ppe_staff_safety',
      name: 'Protective Eyewear',
    ),
    InventorySubcategoryDefinition(
      id: 'disposable_caps',
      categoryId: 'ppe_staff_safety',
      name: 'Disposable Caps',
    ),
    InventorySubcategoryDefinition(
      id: 'sharps_containers',
      categoryId: 'ppe_staff_safety',
      name: 'Sharps Containers',
    ),
    InventorySubcategoryDefinition(
      id: 'biohazard_bags',
      categoryId: 'ppe_staff_safety',
      name: 'Biohazard Bags',
    ),
    InventorySubcategoryDefinition(
      id: 'hazardous_drug_ppe',
      categoryId: 'ppe_staff_safety',
      name: 'Hazardous Drug PPE',
    ),
    InventorySubcategoryDefinition(
      id: 'other_ppe',
      categoryId: 'ppe_staff_safety',
      name: 'Other PPE',
    ),
  ];

  static const _equipmentSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'stethoscopes',
      categoryId: 'medical_equipment',
      name: 'Stethoscopes',
    ),
    InventorySubcategoryDefinition(
      id: 'thermometers',
      categoryId: 'medical_equipment',
      name: 'Thermometers',
    ),
    InventorySubcategoryDefinition(
      id: 'weighing_scales',
      categoryId: 'medical_equipment',
      name: 'Weighing Scales',
    ),
    InventorySubcategoryDefinition(
      id: 'pulse_oximeters',
      categoryId: 'medical_equipment',
      name: 'Pulse Oximeters',
    ),
    InventorySubcategoryDefinition(
      id: 'blood_pressure',
      categoryId: 'medical_equipment',
      name: 'Blood Pressure Monitors',
    ),
    InventorySubcategoryDefinition(
      id: 'patient_monitors',
      categoryId: 'medical_equipment',
      name: 'Patient Monitors',
    ),
    InventorySubcategoryDefinition(
      id: 'ecg',
      categoryId: 'medical_equipment',
      name: 'ECG Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'infusion_pumps',
      categoryId: 'medical_equipment',
      name: 'Infusion & Syringe Pumps',
    ),
    InventorySubcategoryDefinition(
      id: 'oxygen_equipment',
      categoryId: 'medical_equipment',
      name: 'Oxygen Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'nebulizers',
      categoryId: 'medical_equipment',
      name: 'Nebulizers',
    ),
    InventorySubcategoryDefinition(
      id: 'suction',
      categoryId: 'medical_equipment',
      name: 'Suction Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'ultrasound',
      categoryId: 'medical_equipment',
      name: 'Ultrasound Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'xray',
      categoryId: 'medical_equipment',
      name: 'X-Ray Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'imaging_accessories',
      categoryId: 'medical_equipment',
      name: 'Imaging Accessories',
    ),
    InventorySubcategoryDefinition(
      id: 'microscopes',
      categoryId: 'medical_equipment',
      name: 'Microscopes',
    ),
    InventorySubcategoryDefinition(
      id: 'centrifuges',
      categoryId: 'medical_equipment',
      name: 'Centrifuges',
    ),
    InventorySubcategoryDefinition(
      id: 'laboratory_equipment',
      categoryId: 'medical_equipment',
      name: 'Laboratory Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'surgical_instruments',
      categoryId: 'medical_equipment',
      name: 'Surgical Instruments & Sets',
    ),
    InventorySubcategoryDefinition(
      id: 'clippers',
      categoryId: 'medical_equipment',
      name: 'Clippers',
    ),
    InventorySubcategoryDefinition(
      id: 'examination_lights',
      categoryId: 'medical_equipment',
      name: 'Examination Lights',
    ),
    InventorySubcategoryDefinition(
      id: 'resuscitation_equipment',
      categoryId: 'medical_equipment',
      name: 'Resuscitation Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'cold_chain',
      categoryId: 'medical_equipment',
      name: 'Cold Chain & Vaccine Storage',
    ),
    InventorySubcategoryDefinition(
      id: 'refrigerators',
      categoryId: 'medical_equipment',
      name: 'Refrigerators / Vaccine Storage',
    ),
    InventorySubcategoryDefinition(
      id: 'other_equipment',
      categoryId: 'medical_equipment',
      name: 'Other Medical Equipment',
    ),
  ];

  static const _dentalSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'dental_instruments',
      categoryId: 'dental_care',
      name: 'Dental Instruments',
    ),
    InventorySubcategoryDefinition(
      id: 'scaling',
      categoryId: 'dental_care',
      name: 'Dental Scaling Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'polishing',
      categoryId: 'dental_care',
      name: 'Dental Polishing',
    ),
    InventorySubcategoryDefinition(
      id: 'dental_equipment',
      categoryId: 'dental_care',
      name: 'Dental Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'toothbrushes',
      categoryId: 'dental_care',
      name: 'Toothbrushes',
    ),
    InventorySubcategoryDefinition(
      id: 'toothpaste',
      categoryId: 'dental_care',
      name: 'Veterinary Toothpaste',
    ),
    InventorySubcategoryDefinition(
      id: 'oral_rinses',
      categoryId: 'dental_care',
      name: 'Oral Rinses',
    ),
    InventorySubcategoryDefinition(
      id: 'dental_chews',
      categoryId: 'dental_care',
      name: 'Dental Chews',
    ),
    InventorySubcategoryDefinition(
      id: 'periodontal',
      categoryId: 'dental_care',
      name: 'Periodontal Products',
    ),
    InventorySubcategoryDefinition(
      id: 'extraction',
      categoryId: 'dental_care',
      name: 'Extraction Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'other_dental',
      categoryId: 'dental_care',
      name: 'Other Dental Care',
    ),
  ];

  static const _groomingSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'medicated_shampoo',
      categoryId: 'grooming_dermatological',
      name: 'Medicated Shampoo',
    ),
    InventorySubcategoryDefinition(
      id: 'general_shampoo',
      categoryId: 'grooming_dermatological',
      name: 'General Shampoo',
    ),
    InventorySubcategoryDefinition(
      id: 'conditioner',
      categoryId: 'grooming_dermatological',
      name: 'Conditioner',
    ),
    InventorySubcategoryDefinition(
      id: 'coat_care',
      categoryId: 'grooming_dermatological',
      name: 'Coat Care',
    ),
    InventorySubcategoryDefinition(
      id: 'skin_care',
      categoryId: 'grooming_dermatological',
      name: 'Skin Care',
    ),
    InventorySubcategoryDefinition(
      id: 'ear_cleaners',
      categoryId: 'grooming_dermatological',
      name: 'Ear Cleaners',
    ),
    InventorySubcategoryDefinition(
      id: 'eye_cleaners',
      categoryId: 'grooming_dermatological',
      name: 'Eye Cleaners',
    ),
    InventorySubcategoryDefinition(
      id: 'nail_care',
      categoryId: 'grooming_dermatological',
      name: 'Nail Care',
    ),
    InventorySubcategoryDefinition(
      id: 'grooming_clippers',
      categoryId: 'grooming_dermatological',
      name: 'Grooming Clippers & Blades',
    ),
    InventorySubcategoryDefinition(
      id: 'brushes_combs',
      categoryId: 'grooming_dermatological',
      name: 'Brushes & Combs',
    ),
    InventorySubcategoryDefinition(
      id: 'deshedding',
      categoryId: 'grooming_dermatological',
      name: 'De-Shedding Products',
    ),
    InventorySubcategoryDefinition(
      id: 'grooming_sprays',
      categoryId: 'grooming_dermatological',
      name: 'Grooming Sprays',
    ),
    InventorySubcategoryDefinition(
      id: 'paw_care',
      categoryId: 'grooming_dermatological',
      name: 'Paw Care',
    ),
    InventorySubcategoryDefinition(
      id: 'other_grooming',
      categoryId: 'grooming_dermatological',
      name: 'Other Grooming',
    ),
  ];

  static const _reproductionSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'ai_supplies',
      categoryId: 'reproduction_obstetrics',
      name: 'Artificial Insemination Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'semen_collection',
      categoryId: 'reproduction_obstetrics',
      name: 'Semen Collection',
    ),
    InventorySubcategoryDefinition(
      id: 'semen_storage',
      categoryId: 'reproduction_obstetrics',
      name: 'Semen Storage & Handling',
    ),
    InventorySubcategoryDefinition(
      id: 'ai_catheters',
      categoryId: 'reproduction_obstetrics',
      name: 'AI Catheters',
    ),
    InventorySubcategoryDefinition(
      id: 'breeding_supplies',
      categoryId: 'reproduction_obstetrics',
      name: 'Breeding Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'heat_detection',
      categoryId: 'reproduction_obstetrics',
      name: 'Heat Detection',
    ),
    InventorySubcategoryDefinition(
      id: 'pregnancy_diagnosis',
      categoryId: 'reproduction_obstetrics',
      name: 'Pregnancy Diagnosis',
    ),
    InventorySubcategoryDefinition(
      id: 'obstetric_supplies',
      categoryId: 'reproduction_obstetrics',
      name: 'Obstetric Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'calving',
      categoryId: 'reproduction_obstetrics',
      name: 'Calving Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'lambing',
      categoryId: 'reproduction_obstetrics',
      name: 'Lambing Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'kidding',
      categoryId: 'reproduction_obstetrics',
      name: 'Kidding Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'farrowing',
      categoryId: 'reproduction_obstetrics',
      name: 'Farrowing Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'parturition',
      categoryId: 'reproduction_obstetrics',
      name: 'Parturition Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'neonatal_resuscitation',
      categoryId: 'reproduction_obstetrics',
      name: 'Neonatal Resuscitation',
    ),
    InventorySubcategoryDefinition(
      id: 'colostrum',
      categoryId: 'reproduction_obstetrics',
      name: 'Colostrum Products',
    ),
    InventorySubcategoryDefinition(
      id: 'neonatal_feeding',
      categoryId: 'reproduction_obstetrics',
      name: 'Neonatal Feeding',
    ),
    InventorySubcategoryDefinition(
      id: 'umbilical_care',
      categoryId: 'reproduction_obstetrics',
      name: 'Umbilical Care',
    ),
    InventorySubcategoryDefinition(
      id: 'other_reproduction',
      categoryId: 'reproduction_obstetrics',
      name: 'Other Reproduction Supplies',
    ),
  ];

  static const _farmSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'ear_tags',
      categoryId: 'farm_livestock',
      name: 'Ear Tags',
    ),
    InventorySubcategoryDefinition(
      id: 'animal_identification',
      categoryId: 'farm_livestock',
      name: 'Animal Identification',
    ),
    InventorySubcategoryDefinition(
      id: 'tag_applicators',
      categoryId: 'farm_livestock',
      name: 'Tag Applicators',
    ),
    InventorySubcategoryDefinition(
      id: 'castration',
      categoryId: 'farm_livestock',
      name: 'Castration Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'dehorning',
      categoryId: 'farm_livestock',
      name: 'Dehorning / Disbudding',
    ),
    InventorySubcategoryDefinition(
      id: 'cattle_handling',
      categoryId: 'farm_livestock',
      name: 'Cattle Handling',
    ),
    InventorySubcategoryDefinition(
      id: 'sheep_goat_handling',
      categoryId: 'farm_livestock',
      name: 'Sheep & Goat Handling',
    ),
    InventorySubcategoryDefinition(
      id: 'pig_handling',
      categoryId: 'farm_livestock',
      name: 'Pig Handling',
    ),
    InventorySubcategoryDefinition(
      id: 'livestock_restraint',
      categoryId: 'farm_livestock',
      name: 'Livestock Restraint',
    ),
    InventorySubcategoryDefinition(
      id: 'milking',
      categoryId: 'farm_livestock',
      name: 'Milking Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'udder_care',
      categoryId: 'farm_livestock',
      name: 'Udder Care & Teat Dips',
    ),
    InventorySubcategoryDefinition(
      id: 'mastitis_testing',
      categoryId: 'farm_livestock',
      name: 'Mastitis Testing',
    ),
    InventorySubcategoryDefinition(
      id: 'calf_supplies',
      categoryId: 'farm_livestock',
      name: 'Calf Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'lamb_kid_supplies',
      categoryId: 'farm_livestock',
      name: 'Lamb / Kid Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'drenching',
      categoryId: 'farm_livestock',
      name: 'Drenching Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'dosing_guns',
      categoryId: 'farm_livestock',
      name: 'Dosing Guns & Pour-On Applicators',
    ),
    InventorySubcategoryDefinition(
      id: 'vaccination_equipment',
      categoryId: 'farm_livestock',
      name: 'Vaccination Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'farm_biosecurity',
      categoryId: 'farm_livestock',
      name: 'Farm Biosecurity',
    ),
    InventorySubcategoryDefinition(
      id: 'watering',
      categoryId: 'farm_livestock',
      name: 'Watering Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'feeding_equipment',
      categoryId: 'farm_livestock',
      name: 'Feeding Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'other_livestock',
      categoryId: 'farm_livestock',
      name: 'Other Livestock Supplies',
    ),
  ];

  static const _poultrySubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'poultry_feeders',
      categoryId: 'poultry_supplies',
      name: 'Poultry Feeders',
    ),
    InventorySubcategoryDefinition(
      id: 'poultry_drinkers',
      categoryId: 'poultry_supplies',
      name: 'Poultry Drinkers',
    ),
    InventorySubcategoryDefinition(
      id: 'brooding',
      categoryId: 'poultry_supplies',
      name: 'Brooding Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'heat_lamps',
      categoryId: 'poultry_supplies',
      name: 'Heat Lamps',
    ),
    InventorySubcategoryDefinition(
      id: 'chick_supplies',
      categoryId: 'poultry_supplies',
      name: 'Chick Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'debeaking',
      categoryId: 'poultry_supplies',
      name: 'Debeaking Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'poultry_vaccination',
      categoryId: 'poultry_supplies',
      name: 'Vaccination Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'poultry_biosecurity',
      categoryId: 'poultry_supplies',
      name: 'Poultry Biosecurity',
    ),
    InventorySubcategoryDefinition(
      id: 'egg_handling',
      categoryId: 'poultry_supplies',
      name: 'Egg Handling & Egg Trays',
    ),
    InventorySubcategoryDefinition(
      id: 'incubation',
      categoryId: 'poultry_supplies',
      name: 'Incubation & Hatchery Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'poultry_supplements',
      categoryId: 'poultry_supplies',
      name: 'Poultry Supplements',
    ),
    InventorySubcategoryDefinition(
      id: 'litter',
      categoryId: 'poultry_supplies',
      name: 'Litter Management',
    ),
    InventorySubcategoryDefinition(
      id: 'other_poultry',
      categoryId: 'poultry_supplies',
      name: 'Other Poultry Supplies',
    ),
  ];

  static const _petAccessorySubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'collars',
      categoryId: 'pet_accessories',
      name: 'Collars',
    ),
    InventorySubcategoryDefinition(
      id: 'leashes',
      categoryId: 'pet_accessories',
      name: 'Leashes',
    ),
    InventorySubcategoryDefinition(
      id: 'harnesses',
      categoryId: 'pet_accessories',
      name: 'Harnesses',
    ),
    InventorySubcategoryDefinition(
      id: 'muzzles',
      categoryId: 'pet_accessories',
      name: 'Muzzles',
    ),
    InventorySubcategoryDefinition(
      id: 'identification_tags',
      categoryId: 'pet_accessories',
      name: 'Identification Tags',
    ),
    InventorySubcategoryDefinition(
      id: 'bowls_feeders',
      categoryId: 'pet_accessories',
      name: 'Bowls & Feeders',
    ),
    InventorySubcategoryDefinition(
      id: 'waterers',
      categoryId: 'pet_accessories',
      name: 'Waterers',
    ),
    InventorySubcategoryDefinition(
      id: 'beds',
      categoryId: 'pet_accessories',
      name: 'Beds',
    ),
    InventorySubcategoryDefinition(
      id: 'crates',
      categoryId: 'pet_accessories',
      name: 'Crates',
    ),
    InventorySubcategoryDefinition(
      id: 'carriers',
      categoryId: 'pet_accessories',
      name: 'Carriers',
    ),
    InventorySubcategoryDefinition(
      id: 'kennels',
      categoryId: 'pet_accessories',
      name: 'Kennels',
    ),
    InventorySubcategoryDefinition(
      id: 'toys',
      categoryId: 'pet_accessories',
      name: 'Toys',
    ),
    InventorySubcategoryDefinition(
      id: 'training_aids',
      categoryId: 'pet_accessories',
      name: 'Training Aids',
    ),
    InventorySubcategoryDefinition(
      id: 'clothing',
      categoryId: 'pet_accessories',
      name: 'Clothing',
    ),
    InventorySubcategoryDefinition(
      id: 'boots_paw_protection',
      categoryId: 'pet_accessories',
      name: 'Boots / Paw Protection',
    ),
    InventorySubcategoryDefinition(
      id: 'litter',
      categoryId: 'pet_accessories',
      name: 'Litter & Litter Trays',
    ),
    InventorySubcategoryDefinition(
      id: 'waste_bags',
      categoryId: 'pet_accessories',
      name: 'Waste Bags',
    ),
    InventorySubcategoryDefinition(
      id: 'travel',
      categoryId: 'pet_accessories',
      name: 'Travel Accessories',
    ),
    InventorySubcategoryDefinition(
      id: 'protective_collars',
      categoryId: 'pet_accessories',
      name: 'Protective / Elizabethan Collars',
    ),
    InventorySubcategoryDefinition(
      id: 'grooming_accessories',
      categoryId: 'pet_accessories',
      name: 'Grooming Accessories',
    ),
    InventorySubcategoryDefinition(
      id: 'other_pet_accessories',
      categoryId: 'pet_accessories',
      name: 'Other Pet Accessories',
    ),
  ];

  static const _housingSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'cages',
      categoryId: 'housing_handling',
      name: 'Cages',
    ),
    InventorySubcategoryDefinition(
      id: 'kennels',
      categoryId: 'housing_handling',
      name: 'Kennels',
    ),
    InventorySubcategoryDefinition(
      id: 'crates',
      categoryId: 'housing_handling',
      name: 'Crates',
    ),
    InventorySubcategoryDefinition(
      id: 'carriers',
      categoryId: 'housing_handling',
      name: 'Carriers',
    ),
    InventorySubcategoryDefinition(
      id: 'restraint',
      categoryId: 'housing_handling',
      name: 'Restraint Equipment',
    ),
    InventorySubcategoryDefinition(
      id: 'leads',
      categoryId: 'housing_handling',
      name: 'Leads',
    ),
    InventorySubcategoryDefinition(
      id: 'handling_poles',
      categoryId: 'housing_handling',
      name: 'Handling Poles',
    ),
    InventorySubcategoryDefinition(
      id: 'livestock_restraints',
      categoryId: 'housing_handling',
      name: 'Livestock Restraints',
    ),
    InventorySubcategoryDefinition(
      id: 'animal_nets',
      categoryId: 'housing_handling',
      name: 'Animal Nets',
    ),
    InventorySubcategoryDefinition(
      id: 'bedding',
      categoryId: 'housing_handling',
      name: 'Bedding',
    ),
    InventorySubcategoryDefinition(
      id: 'heat_sources',
      categoryId: 'housing_handling',
      name: 'Heat Sources',
    ),
    InventorySubcategoryDefinition(
      id: 'housing_accessories',
      categoryId: 'housing_handling',
      name: 'Housing Accessories',
    ),
    InventorySubcategoryDefinition(
      id: 'other_housing',
      categoryId: 'housing_handling',
      name: 'Other Housing & Handling',
    ),
  ];

  static const _emergencySubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'emergency_kits',
      categoryId: 'emergency_supplies',
      name: 'Emergency Kits',
    ),
    InventorySubcategoryDefinition(
      id: 'resuscitation',
      categoryId: 'emergency_supplies',
      name: 'Resuscitation Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'oxygen_masks',
      categoryId: 'emergency_supplies',
      name: 'Oxygen Masks & Tubing',
    ),
    InventorySubcategoryDefinition(
      id: 'ambu_bags',
      categoryId: 'emergency_supplies',
      name: 'Ambu / Resuscitation Bags',
    ),
    InventorySubcategoryDefinition(
      id: 'emergency_catheters',
      categoryId: 'emergency_supplies',
      name: 'Emergency Catheters',
    ),
    InventorySubcategoryDefinition(
      id: 'emergency_airways',
      categoryId: 'emergency_supplies',
      name: 'Emergency Airways',
    ),
    InventorySubcategoryDefinition(
      id: 'emergency_dressings',
      categoryId: 'emergency_supplies',
      name: 'Emergency Dressings',
    ),
    InventorySubcategoryDefinition(
      id: 'emergency_procedure_kits',
      categoryId: 'emergency_supplies',
      name: 'Emergency Procedure Kits',
    ),
    InventorySubcategoryDefinition(
      id: 'critical_care',
      categoryId: 'emergency_supplies',
      name: 'Critical Care Consumables',
    ),
    InventorySubcategoryDefinition(
      id: 'other_emergency',
      categoryId: 'emergency_supplies',
      name: 'Other Emergency Supplies',
    ),
  ];

  static const _pharmacySubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'medicine_bottles',
      categoryId: 'pharmacy_supplies',
      name: 'Medicine Bottles',
    ),
    InventorySubcategoryDefinition(
      id: 'tablet_containers',
      categoryId: 'pharmacy_supplies',
      name: 'Tablet Containers',
    ),
    InventorySubcategoryDefinition(
      id: 'dispensing_bags',
      categoryId: 'pharmacy_supplies',
      name: 'Dispensing Bags',
    ),
    InventorySubcategoryDefinition(
      id: 'prescription_labels',
      categoryId: 'pharmacy_supplies',
      name: 'Prescription & Medication Labels',
    ),
    InventorySubcategoryDefinition(
      id: 'measuring',
      categoryId: 'pharmacy_supplies',
      name: 'Measuring Cups & Oral Syringes',
    ),
    InventorySubcategoryDefinition(
      id: 'pill_cutters_counters',
      categoryId: 'pharmacy_supplies',
      name: 'Pill Cutters & Counters',
    ),
    InventorySubcategoryDefinition(
      id: 'compounding',
      categoryId: 'pharmacy_supplies',
      name: 'Compounding Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'dispensing_accessories',
      categoryId: 'pharmacy_supplies',
      name: 'Dispensing Accessories',
    ),
    InventorySubcategoryDefinition(
      id: 'other_pharmacy',
      categoryId: 'pharmacy_supplies',
      name: 'Other Pharmacy Supplies',
    ),
  ];

  static const _cleaningSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'detergents',
      categoryId: 'cleaning_facility',
      name: 'Detergents',
    ),
    InventorySubcategoryDefinition(
      id: 'floor_cleaners',
      categoryId: 'cleaning_facility',
      name: 'Floor Cleaners',
    ),
    InventorySubcategoryDefinition(
      id: 'kennel_cleaners',
      categoryId: 'cleaning_facility',
      name: 'Kennel Cleaners',
    ),
    InventorySubcategoryDefinition(
      id: 'laundry',
      categoryId: 'cleaning_facility',
      name: 'Laundry Products',
    ),
    InventorySubcategoryDefinition(
      id: 'paper_products',
      categoryId: 'cleaning_facility',
      name: 'Paper Towels & Tissue',
    ),
    InventorySubcategoryDefinition(
      id: 'mops_brushes',
      categoryId: 'cleaning_facility',
      name: 'Mops & Brushes',
    ),
    InventorySubcategoryDefinition(
      id: 'buckets',
      categoryId: 'cleaning_facility',
      name: 'Buckets',
    ),
    InventorySubcategoryDefinition(
      id: 'waste_bins_bags',
      categoryId: 'cleaning_facility',
      name: 'Waste Bins & Bags',
    ),
    InventorySubcategoryDefinition(
      id: 'odour_control',
      categoryId: 'cleaning_facility',
      name: 'Odour Control',
    ),
    InventorySubcategoryDefinition(
      id: 'pest_control',
      categoryId: 'cleaning_facility',
      name: 'Pest Control',
    ),
    InventorySubcategoryDefinition(
      id: 'facility_consumables',
      categoryId: 'cleaning_facility',
      name: 'Facility Consumables',
    ),
    InventorySubcategoryDefinition(
      id: 'other_cleaning',
      categoryId: 'cleaning_facility',
      name: 'Other Cleaning Supplies',
    ),
  ];

  static const _officeSubcategories = <InventorySubcategoryDefinition>[
    InventorySubcategoryDefinition(
      id: 'printing_paper',
      categoryId: 'office_admin',
      name: 'Printing Paper',
    ),
    InventorySubcategoryDefinition(
      id: 'receipt_rolls',
      categoryId: 'office_admin',
      name: 'Receipt Rolls',
    ),
    InventorySubcategoryDefinition(
      id: 'printer_supplies',
      categoryId: 'office_admin',
      name: 'Printer Supplies',
    ),
    InventorySubcategoryDefinition(
      id: 'labels',
      categoryId: 'office_admin',
      name: 'Labels',
    ),
    InventorySubcategoryDefinition(
      id: 'stationery',
      categoryId: 'office_admin',
      name: 'Stationery',
    ),
    InventorySubcategoryDefinition(
      id: 'record_materials',
      categoryId: 'office_admin',
      name: 'Record Materials',
    ),
    InventorySubcategoryDefinition(
      id: 'packaging',
      categoryId: 'office_admin',
      name: 'Packaging',
    ),
    InventorySubcategoryDefinition(
      id: 'other_admin',
      categoryId: 'office_admin',
      name: 'Other Administrative Supplies',
    ),
  ];

  static InventoryCategoryDefinition? byId(String? id) {
    for (final category in all) {
      if (category.id == id) return category;
    }
    return null;
  }

  static InventoryCategoryDefinition? byValue(String? value) {
    if (value == null) return null;
    final normalized = normalizeInventoryCatalogueSearch(value);
    final compact = _compactInventoryCatalogueSearch(value);
    if (normalized.isEmpty) return null;
    for (final category in all) {
      if (category.id == normalized ||
          category.searchableText.contains(normalized) ||
          _compactInventoryCatalogueSearch(
            category.searchableText,
          ).contains(compact)) {
        return category;
      }
    }
    return null;
  }

  static String canonicalId(String legacyValue) {
    final normalized = normalizeInventoryCatalogueSearch(legacyValue);
    if (normalized.isEmpty) return customCategoryId;
    final direct = byValue(legacyValue);
    if (direct != null) return direct.id;
    if (normalized.contains('vaccine') || normalized == 'biologics') {
      return 'vaccines';
    }
    if (normalized.contains('drug') ||
        normalized.contains('medicine') ||
        normalized.contains('medication') ||
        normalized.contains('pharmaceutical') ||
        normalized.contains('antibiotic') ||
        normalized.contains('antiparasitic') ||
        normalized.contains('nsaid') ||
        normalized.contains('anaesthetic') ||
        normalized.contains('anesthetic')) {
      return 'drugs';
    }
    if (normalized.contains('fluid') || normalized.contains('electrolyte')) {
      return 'fluids_electrolytes';
    }
    if (normalized.contains('supplement') || normalized.contains('vitamin')) {
      return 'supplements';
    }
    if (normalized.contains('feed') ||
        normalized.contains('food') ||
        normalized.contains('nutrition')) {
      return 'nutrition_feed';
    }
    if (normalized.contains('laboratory') ||
        normalized.contains('reagent') ||
        normalized.contains('diagnostic') ||
        normalized.contains('test kit')) {
      return 'diagnostic_laboratory';
    }
    if (normalized.contains('consumable')) return 'clinical_consumables';
    if (normalized.contains('surg')) return 'surgical_supplies';
    if (normalized.contains('wound') || normalized.contains('bandag')) {
      return 'wound_care';
    }
    if (normalized.contains('disinfect') || normalized.contains('infection')) {
      return 'infection_control';
    }
    if (normalized == 'ppe' || normalized.contains('safety')) {
      return 'ppe_staff_safety';
    }
    if (normalized.contains('equipment') || normalized.contains('instrument')) {
      return 'medical_equipment';
    }
    if (normalized.contains('dental')) return 'dental_care';
    if (normalized.contains('groom') || normalized.contains('dermat')) {
      return 'grooming_dermatological';
    }
    if (normalized.contains('reproduct') || normalized.contains('breeding')) {
      return 'reproduction_obstetrics';
    }
    if (normalized.contains('farm') || normalized.contains('livestock')) {
      return 'farm_livestock';
    }
    if (normalized.contains('poultry')) return 'poultry_supplies';
    if (normalized.contains('accessor') || normalized.contains('retail')) {
      return 'pet_accessories';
    }
    if (normalized.contains('housing') || normalized.contains('handling')) {
      return 'housing_handling';
    }
    if (normalized.contains('emergency') || normalized.contains('critical')) {
      return 'emergency_supplies';
    }
    if (normalized.contains('dispens') || normalized.contains('pharmacy')) {
      return 'pharmacy_supplies';
    }
    if (normalized.contains('clean') || normalized.contains('facility')) {
      return 'cleaning_facility';
    }
    if (normalized.contains('office') || normalized.contains('admin')) {
      return 'office_admin';
    }
    return customCategoryId;
  }

  static String displayNameFor(String? categoryId, String? storedValue) {
    final canonical = byId(canonicalId(categoryId ?? storedValue ?? ''));
    final value = storedValue?.trim() ?? '';
    if (canonical == null) return value.isEmpty ? 'Other' : value;
    if (canonical.id == customCategoryId && value.isNotEmpty) return value;
    return canonical.name;
  }

  static List<InventorySubcategoryDefinition> subcategoriesFor(
    String? categoryId,
  ) => byId(canonicalId(categoryId ?? ''))?.subcategories ?? const [];

  static InventorySubcategoryDefinition? subcategoryById(
    String? categoryId,
    String? subcategoryId,
  ) {
    if (subcategoryId == null) return null;
    for (final item in subcategoriesFor(categoryId)) {
      if (item.id == subcategoryId) return item;
    }
    return null;
  }

  static InventorySubcategoryDefinition? resolveSubcategory(
    String? categoryId,
    String? value,
  ) {
    final normalized = normalizeInventoryCatalogueSearch(value ?? '');
    if (normalized.isEmpty) return null;
    for (final item in subcategoriesFor(categoryId)) {
      if (item.id == normalized || item.matches(value!)) return item;
    }
    return null;
  }

  static String? canonicalSubcategoryId(String? categoryId, String? value) =>
      resolveSubcategory(categoryId, value)?.id;

  static String subcategoryDisplayName(
    String? categoryId,
    String? subcategoryId,
    String? storedValue,
  ) {
    final canonical = subcategoryById(categoryId, subcategoryId);
    if (canonical != null) return canonical.name;
    final value = storedValue?.trim() ?? '';
    return value.isEmpty ? 'Not specified' : value;
  }
}

class InventoryAccess {
  const InventoryAccess._();

  static String viewPermission(String categoryId) =>
      'inventory.category.$categoryId.view';

  static String sellPermission(String categoryId) =>
      'inventory.category.$categoryId.sell';

  static Set<String> configuredViewCategories(Set<String> permissions) => {
    for (final category in InventoryCategories.all)
      if (permissions.contains(viewPermission(category.id)) ||
          category.legacyIds.any(
            (id) => permissions.contains(viewPermission(id)),
          ))
        category.id,
  };

  static Set<String> configuredSellCategories(Set<String> permissions) => {
    for (final category in InventoryCategories.all)
      if (permissions.contains(sellPermission(category.id)) ||
          category.legacyIds.any(
            (id) => permissions.contains(sellPermission(id)),
          ))
        category.id,
  };

  static Set<String> defaultCategoriesForRole(String role) => switch (role) {
    'Pharmacist' => {'drugs', 'vaccines', 'supplements'},
    'Laboratory Staff' => {'diagnostic_laboratory', 'medical_equipment'},
    'Veterinary Nurse' => {'vaccines', 'clinical_consumables'},
    'Veterinarian' => {
      'drugs',
      'vaccines',
      'clinical_consumables',
      'surgical_supplies',
    },
    'Cashier' || 'Sales Representative' => {
      for (final category in InventoryCategories.all)
        if (category.isSellable) category.id,
    },
    _ => const <String>{},
  };
}

String formatNaira(num amount) =>
    'NGN ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (match) => ',')}';
