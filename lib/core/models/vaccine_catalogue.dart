import 'animal_catalogue.dart';

enum VaccineScheduleFilter {
  all,
  dueNow,
  dueToday,
  upcoming,
  overdue,
  followUp,
  completed,
}

/// The dashboard and the Vaccine Schedule use this same reminder predicate.
/// A completed dose that has a future booster carries a new pending reminder;
/// the completed source reminder itself is never actionable again.
bool isVaccinationActionRequired(
  String reminderStatus,
  DateTime? dueDate,
  DateTime now,
) {
  if (dueDate == null) return false;
  if (reminderStatus.trim().toLowerCase() != 'pending') return false;
  final endOfToday = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 1));
  return dueDate.isBefore(endOfToday);
}

String vaccinationReminderDisplayStatus({
  required String reminderStatus,
  required DateTime? dueDate,
  required DateTime now,
}) {
  final normalized = reminderStatus.trim().toLowerCase();
  if (normalized == 'cancelled') return 'Cancelled';
  if (normalized == 'completed') return 'Completed';
  if (dueDate == null) return 'Completed';

  final startOfToday = DateTime(now.year, now.month, now.day);
  if (dueDate.isBefore(startOfToday)) return 'Overdue';
  if (dueDate.isBefore(startOfToday.add(const Duration(days: 1)))) {
    return 'Due Today';
  }
  return 'Upcoming';
}

enum VaccineRoute {
  subcutaneous,
  intramuscular,
  intranasal,
  oral,
  intradermal,
  scarification,
}

extension VaccineRouteLabel on VaccineRoute {
  String get label => switch (this) {
    VaccineRoute.subcutaneous => 'Subcutaneous',
    VaccineRoute.intramuscular => 'Intramuscular',
    VaccineRoute.intranasal => 'Intranasal',
    VaccineRoute.oral => 'Oral',
    VaccineRoute.intradermal => 'Intradermal',
    VaccineRoute.scarification => 'Scarification',
  };
}

class VaccineProtocolDefinition {
  const VaccineProtocolDefinition({
    required this.id,
    required this.speciesId,
    required this.name,
    required this.education,
    required this.intervalDays,
    required this.routes,
    this.subtitle,
    this.aliases = const [],
    this.isCore = false,
  });

  final String id;
  final String speciesId;
  final String name;
  final String education;
  final int intervalDays;
  final List<VaccineRoute> routes;
  final String? subtitle;
  final List<String> aliases;
  final bool isCore;

  VaccineRoute get defaultRoute => routes.first;
  DateTime suggestedDueDate(DateTime dateGiven) =>
      dateGiven.add(Duration(days: intervalDays));
}

class VaccineCatalogue {
  const VaccineCatalogue._();

  static const protocols = <VaccineProtocolDefinition>[
    VaccineProtocolDefinition(
      id: 'vax_dog_dhlpp',
      speciesId: 'species_dog',
      name: 'DHLPP',
      subtitle: 'Core combination vaccine',
      intervalDays: 28,
      routes: [VaccineRoute.subcutaneous],
      isCore: true,
      aliases: ['DHPP'],
      education:
          'Protects against common canine viral disease and leptospirosis. Primary series timing and booster intervals must follow the product label and clinic policy.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_dog_rabies',
      speciesId: 'species_dog',
      name: 'Rabies',
      subtitle: 'Core / regulatory vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.subcutaneous, VaccineRoute.intramuscular],
      isCore: true,
      education:
          'Use an approved rabies vaccine according to local law and the manufacturer label. Confirm the legally valid booster interval for this product.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_dog_bordetella',
      speciesId: 'species_dog',
      name: 'Bordetella',
      subtitle: 'Risk-based respiratory protection',
      intervalDays: 365,
      routes: [VaccineRoute.intranasal, VaccineRoute.subcutaneous],
      education:
          'Consider for patients exposed to boarding, grooming, shows, or high-density dog contact. Follow product-specific revaccination guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_cat_fvrcp',
      speciesId: 'species_cat',
      name: 'FVRCP',
      subtitle: 'Core feline combination vaccine',
      intervalDays: 28,
      routes: [VaccineRoute.subcutaneous],
      isCore: true,
      education:
          'Protects against feline viral rhinotracheitis, calicivirus and panleukopenia. Use a series and booster plan appropriate to the patient and product label.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_cat_rabies',
      speciesId: 'species_cat',
      name: 'Rabies',
      subtitle: 'Core / regulatory vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.subcutaneous, VaccineRoute.intramuscular],
      isCore: true,
      education:
          'Use an approved feline rabies product according to local law and manufacturer guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_cattle_fmd',
      speciesId: 'species_cattle',
      name: 'Foot-and-Mouth Disease',
      subtitle: 'Programme-dependent cattle vaccine',
      intervalDays: 180,
      routes: [VaccineRoute.intramuscular, VaccineRoute.subcutaneous],
      education:
          'Use only within an approved local disease-control programme and according to the labelled product schedule.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_cattle_cbpp',
      speciesId: 'species_cattle',
      name: 'CBPP',
      subtitle: 'Programme-dependent cattle vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.subcutaneous],
      education:
          'Contagious bovine pleuropneumonia vaccination should follow applicable veterinary authority and manufacturer guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_goat_ppr',
      speciesId: 'species_goat',
      name: 'PPR',
      subtitle: 'Small-ruminant vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.subcutaneous],
      isCore: true,
      education:
          'Peste des petits ruminants vaccination is for small ruminants and should follow local control-programme guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_sheep_ppr',
      speciesId: 'species_sheep',
      name: 'PPR',
      subtitle: 'Small-ruminant vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.subcutaneous],
      isCore: true,
      education:
          'Peste des petits ruminants vaccination is for small ruminants and should follow local control-programme guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_goat_orf',
      speciesId: 'species_goat',
      name: 'Orf',
      subtitle: 'Small-ruminant risk-based vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.scarification],
      education:
          'Use only where clinically indicated and in accordance with product and local disease-control guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_sheep_orf',
      speciesId: 'species_sheep',
      name: 'Orf',
      subtitle: 'Small-ruminant risk-based vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.scarification],
      education:
          'Use only where clinically indicated and in accordance with product and local disease-control guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_chicken_newcastle',
      speciesId: 'species_chicken',
      name: 'Newcastle Disease',
      subtitle: 'Poultry vaccination programme',
      intervalDays: 90,
      routes: [VaccineRoute.oral, VaccineRoute.intranasal],
      education:
          'Use a flock programme, local disease risk and manufacturer directions to determine timing and administration.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_rabbit_rhd',
      speciesId: 'species_rabbit',
      name: 'Rabbit Haemorrhagic Disease',
      subtitle: 'Rabbit risk-based vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.subcutaneous],
      education:
          'Use an approved rabbit vaccine according to local disease risk and manufacturer guidance.',
    ),
    VaccineProtocolDefinition(
      id: 'vax_parrot_polyomavirus',
      speciesId: 'species_parrot',
      name: 'Avian Polyomavirus',
      subtitle: 'Psittacine risk-based vaccine',
      intervalDays: 365,
      routes: [VaccineRoute.intramuscular, VaccineRoute.subcutaneous],
      education:
          'Use only under avian-veterinary guidance and in line with the product label and regional availability.',
    ),
  ];

  static List<VaccineProtocolDefinition> forSpecies(String speciesId) =>
      protocols.where((protocol) => protocol.speciesId == speciesId).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  static VaccineProtocolDefinition? byId(String? id) {
    for (final protocol in protocols) {
      if (protocol.id == id) return protocol;
    }
    return null;
  }

  static bool isCompatible({
    required String speciesId,
    required String vaccineName,
  }) {
    final normalized = vaccineName.trim().toLowerCase();
    return forSpecies(speciesId).any(
      (protocol) =>
          protocol.name.toLowerCase() == normalized ||
          protocol.aliases.any((alias) => alias.toLowerCase() == normalized),
    );
  }

  static AnimalSpeciesOption? speciesForLegacyPatient(String? species) =>
      AnimalCatalogue.speciesForDisplayName(species);
}
