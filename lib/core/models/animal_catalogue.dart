enum AnimalCategory {
  companion('Companion Animals'),
  farm('Farm and Production Animals'),
  equine('Equine'),
  birds('Poultry and Birds'),
  avian('Companion and Exotic Birds'),
  reptile('Reptiles'),
  amphibian('Amphibians'),
  aquatic('Aquatic Animals'),
  laboratoryAnimal('Laboratory Animals'),
  wildlife('Wildlife'),
  exotic('Exotic Animals'),
  other('Other');

  const AnimalCategory(this.label);
  final String label;
}

class AnimalSpeciesOption {
  const AnimalSpeciesOption({
    required this.id,
    required this.displayName,
    required this.category,
    this.veterinaryName,
    this.searchAliases = const [],
    this.allowsCustomSpecies = false,
  });

  final String id;
  final String displayName;
  final String? veterinaryName;
  final AnimalCategory category;
  final List<String> searchAliases;
  final bool allowsCustomSpecies;

  String get displayLabel =>
      veterinaryName == null ? displayName : '$displayName - $veterinaryName';

  String get searchableText =>
      '$displayName ${veterinaryName ?? ''} ${searchAliases.join(' ')}'
          .toLowerCase();
}

class AnimalBreedOption {
  const AnimalBreedOption({
    required this.id,
    required this.speciesId,
    required this.displayName,
    this.aliases = const [],
    this.allowsCustomBreed = false,
    this.isUnknownOption = false,
  });

  final String id;
  final String speciesId;
  final String displayName;
  final List<String> aliases;
  final bool allowsCustomBreed;
  final bool isUnknownOption;

  String get searchableText =>
      '$displayName ${aliases.join(' ')}'.toLowerCase();
}

class AnimalCatalogue {
  const AnimalCatalogue._();

  static const species = <AnimalSpeciesOption>[
    AnimalSpeciesOption(
      id: 'species_dog',
      displayName: 'Dog',
      veterinaryName: 'Canine',
      searchAliases: ['canid', 'puppy'],
      category: AnimalCategory.companion,
    ),
    AnimalSpeciesOption(
      id: 'species_cat',
      displayName: 'Cat',
      veterinaryName: 'Feline',
      searchAliases: ['kitten'],
      category: AnimalCategory.companion,
    ),
    AnimalSpeciesOption(
      id: 'species_rabbit',
      displayName: 'Rabbit',
      category: AnimalCategory.companion,
    ),
    AnimalSpeciesOption(
      id: 'species_guinea_pig',
      displayName: 'Guinea Pig',
      category: AnimalCategory.companion,
    ),
    AnimalSpeciesOption(
      id: 'species_hamster',
      displayName: 'Hamster',
      category: AnimalCategory.companion,
    ),
    AnimalSpeciesOption(
      id: 'species_ferret',
      displayName: 'Ferret',
      category: AnimalCategory.companion,
    ),
    AnimalSpeciesOption(
      id: 'species_cattle',
      displayName: 'Cattle',
      veterinaryName: 'Bovine',
      searchAliases: ['cow', 'bull', 'calf'],
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_goat',
      displayName: 'Goat',
      veterinaryName: 'Caprine',
      searchAliases: ['kid'],
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_sheep',
      displayName: 'Sheep',
      veterinaryName: 'Ovine',
      searchAliases: ['ewe', 'ram', 'lamb'],
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_pig',
      displayName: 'Pig',
      veterinaryName: 'Porcine',
      searchAliases: ['swine', 'hog'],
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_horse',
      displayName: 'Horse',
      veterinaryName: 'Equine',
      category: AnimalCategory.equine,
    ),
    AnimalSpeciesOption(
      id: 'species_donkey',
      displayName: 'Donkey',
      category: AnimalCategory.equine,
    ),
    AnimalSpeciesOption(
      id: 'species_camel',
      displayName: 'Camel',
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_chicken',
      displayName: 'Chicken',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_turkey',
      displayName: 'Turkey',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_duck',
      displayName: 'Duck',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_goose',
      displayName: 'Goose',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_guinea_fowl',
      displayName: 'Guinea Fowl',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_quail',
      displayName: 'Quail',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_pigeon',
      displayName: 'Pigeon',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_parrot',
      displayName: 'Parrot',
      veterinaryName: 'Psittacine',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_canary_finch',
      displayName: 'Canary / Finch',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_tortoise',
      displayName: 'Tortoise',
      category: AnimalCategory.reptile,
    ),
    AnimalSpeciesOption(
      id: 'species_turtle',
      displayName: 'Turtle',
      category: AnimalCategory.reptile,
    ),
    AnimalSpeciesOption(
      id: 'species_snake',
      displayName: 'Snake',
      category: AnimalCategory.reptile,
    ),
    AnimalSpeciesOption(
      id: 'species_lizard',
      displayName: 'Lizard',
      category: AnimalCategory.reptile,
    ),
    AnimalSpeciesOption(
      id: 'species_fish',
      displayName: 'Fish',
      category: AnimalCategory.aquatic,
    ),
    AnimalSpeciesOption(
      id: 'species_gerbil',
      displayName: 'Gerbil',
      category: AnimalCategory.companion,
      searchAliases: ['mongolian gerbil'],
    ),
    AnimalSpeciesOption(
      id: 'species_chinchilla',
      displayName: 'Chinchilla',
      category: AnimalCategory.companion,
    ),
    AnimalSpeciesOption(
      id: 'species_mouse',
      displayName: 'Mouse',
      veterinaryName: 'Murine',
      category: AnimalCategory.laboratoryAnimal,
      searchAliases: ['mice'],
    ),
    AnimalSpeciesOption(
      id: 'species_rat',
      displayName: 'Rat',
      veterinaryName: 'Murine',
      category: AnimalCategory.laboratoryAnimal,
    ),
    AnimalSpeciesOption(
      id: 'species_buffalo',
      displayName: 'Buffalo',
      veterinaryName: 'Bubaline',
      category: AnimalCategory.farm,
      searchAliases: ['water buffalo'],
    ),
    AnimalSpeciesOption(
      id: 'species_llama',
      displayName: 'Llama',
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_alpaca',
      displayName: 'Alpaca',
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_deer',
      displayName: 'Deer',
      veterinaryName: 'Cervine',
      category: AnimalCategory.farm,
    ),
    AnimalSpeciesOption(
      id: 'species_mule',
      displayName: 'Mule',
      category: AnimalCategory.equine,
    ),
    AnimalSpeciesOption(
      id: 'species_pony',
      displayName: 'Pony',
      category: AnimalCategory.equine,
    ),
    AnimalSpeciesOption(
      id: 'species_dove',
      displayName: 'Dove',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_ostrich',
      displayName: 'Ostrich',
      veterinaryName: 'Ratite',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_emu',
      displayName: 'Emu',
      veterinaryName: 'Ratite',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_peacock',
      displayName: 'Peacock',
      veterinaryName: 'Peafowl',
      category: AnimalCategory.birds,
    ),
    AnimalSpeciesOption(
      id: 'species_african_grey_parrot',
      displayName: 'African Grey Parrot',
      veterinaryName: 'Psittacine',
      category: AnimalCategory.avian,
      searchAliases: ['african grey'],
    ),
    AnimalSpeciesOption(
      id: 'species_budgerigar',
      displayName: 'Budgerigar',
      veterinaryName: 'Psittacine',
      category: AnimalCategory.avian,
      searchAliases: ['budgie'],
    ),
    AnimalSpeciesOption(
      id: 'species_cockatiel',
      displayName: 'Cockatiel',
      veterinaryName: 'Psittacine',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_cockatoo',
      displayName: 'Cockatoo',
      veterinaryName: 'Psittacine',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_macaw',
      displayName: 'Macaw',
      veterinaryName: 'Psittacine',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_lovebird',
      displayName: 'Lovebird',
      veterinaryName: 'Psittacine',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_canary',
      displayName: 'Canary',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_finch',
      displayName: 'Finch',
      category: AnimalCategory.avian,
    ),
    AnimalSpeciesOption(
      id: 'species_mynah',
      displayName: 'Mynah',
      category: AnimalCategory.avian,
      searchAliases: ['myna'],
    ),
    AnimalSpeciesOption(
      id: 'species_gecko',
      displayName: 'Gecko',
      category: AnimalCategory.reptile,
    ),
    AnimalSpeciesOption(
      id: 'species_iguana',
      displayName: 'Iguana',
      category: AnimalCategory.reptile,
    ),
    AnimalSpeciesOption(
      id: 'species_chameleon',
      displayName: 'Chameleon',
      category: AnimalCategory.reptile,
    ),
    AnimalSpeciesOption(
      id: 'species_monitor_lizard',
      displayName: 'Monitor Lizard',
      veterinaryName: 'Varanid',
      category: AnimalCategory.reptile,
      searchAliases: ['monitor'],
    ),
    AnimalSpeciesOption(
      id: 'species_crocodilian',
      displayName: 'Crocodilian',
      category: AnimalCategory.reptile,
      searchAliases: ['crocodile', 'alligator'],
    ),
    AnimalSpeciesOption(
      id: 'species_frog',
      displayName: 'Frog',
      veterinaryName: 'Anuran',
      category: AnimalCategory.amphibian,
    ),
    AnimalSpeciesOption(
      id: 'species_toad',
      displayName: 'Toad',
      veterinaryName: 'Anuran',
      category: AnimalCategory.amphibian,
    ),
    AnimalSpeciesOption(
      id: 'species_salamander',
      displayName: 'Salamander',
      veterinaryName: 'Caudate',
      category: AnimalCategory.amphibian,
    ),
    AnimalSpeciesOption(
      id: 'species_newt',
      displayName: 'Newt',
      veterinaryName: 'Caudate',
      category: AnimalCategory.amphibian,
    ),
    AnimalSpeciesOption(
      id: 'species_freshwater_fish',
      displayName: 'Freshwater Fish',
      category: AnimalCategory.aquatic,
    ),
    AnimalSpeciesOption(
      id: 'species_marine_fish',
      displayName: 'Marine Fish',
      category: AnimalCategory.aquatic,
      searchAliases: ['saltwater fish'],
    ),
    AnimalSpeciesOption(
      id: 'species_ornamental_fish',
      displayName: 'Ornamental Fish',
      category: AnimalCategory.aquatic,
      searchAliases: ['aquarium fish'],
    ),
    AnimalSpeciesOption(
      id: 'species_koi',
      displayName: 'Koi',
      category: AnimalCategory.aquatic,
      searchAliases: ['koi carp'],
    ),
    AnimalSpeciesOption(
      id: 'species_goldfish',
      displayName: 'Goldfish',
      category: AnimalCategory.aquatic,
    ),
    AnimalSpeciesOption(
      id: 'species_crustacean',
      displayName: 'Crustacean',
      category: AnimalCategory.aquatic,
      searchAliases: ['shrimp', 'crab', 'lobster'],
    ),
    AnimalSpeciesOption(
      id: 'species_mollusc',
      displayName: 'Mollusc',
      category: AnimalCategory.aquatic,
      searchAliases: ['mollusk', 'snail', 'clam'],
    ),
    AnimalSpeciesOption(
      id: 'species_monkey',
      displayName: 'Monkey',
      veterinaryName: 'Primate',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_ape',
      displayName: 'Ape',
      veterinaryName: 'Primate',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_antelope',
      displayName: 'Antelope',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_elephant',
      displayName: 'Elephant',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_big_cat',
      displayName: 'Big Cat',
      veterinaryName: 'Felid',
      category: AnimalCategory.wildlife,
      searchAliases: ['lion', 'tiger', 'leopard', 'cheetah'],
    ),
    AnimalSpeciesOption(
      id: 'species_small_wild_cat',
      displayName: 'Small Wild Cat',
      veterinaryName: 'Felid',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_fox',
      displayName: 'Fox',
      veterinaryName: 'Canid',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_hyena',
      displayName: 'Hyena',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_hedgehog',
      displayName: 'Hedgehog',
      category: AnimalCategory.exotic,
    ),
    AnimalSpeciesOption(
      id: 'species_pangolin',
      displayName: 'Pangolin',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_bat',
      displayName: 'Bat',
      veterinaryName: 'Chiropteran',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_squirrel',
      displayName: 'Squirrel',
      veterinaryName: 'Rodent',
      category: AnimalCategory.wildlife,
    ),
    AnimalSpeciesOption(
      id: 'species_other_reptile',
      displayName: 'Other Reptile',
      category: AnimalCategory.reptile,
      allowsCustomSpecies: true,
    ),
    AnimalSpeciesOption(
      id: 'species_other_aquatic',
      displayName: 'Other Aquatic Animal',
      category: AnimalCategory.aquatic,
      allowsCustomSpecies: true,
    ),
    AnimalSpeciesOption(
      id: 'species_other_wildlife',
      displayName: 'Other Wildlife',
      category: AnimalCategory.wildlife,
      allowsCustomSpecies: true,
    ),
    AnimalSpeciesOption(
      id: 'species_unknown',
      displayName: 'Unknown / Not Specified',
      category: AnimalCategory.other,
      searchAliases: ['unknown animal'],
    ),

    AnimalSpeciesOption(
      id: 'species_other_companion',
      displayName: 'Other Companion Animal',
      category: AnimalCategory.companion,
      allowsCustomSpecies: true,
    ),
    AnimalSpeciesOption(
      id: 'species_other_farm',
      displayName: 'Other Farm Animal',
      category: AnimalCategory.farm,
      allowsCustomSpecies: true,
    ),
    AnimalSpeciesOption(
      id: 'species_other_bird',
      displayName: 'Other Bird',
      category: AnimalCategory.birds,
      allowsCustomSpecies: true,
    ),
    AnimalSpeciesOption(
      id: 'species_other_exotic',
      displayName: 'Other Exotic Animal',
      category: AnimalCategory.exotic,
      allowsCustomSpecies: true,
    ),
  ];

  static const Map<String, List<String>> _breedNames = {
    'species_dog': [
      'Akita',
      'Alaskan Malamute',
      'American Pit Bull Terrier',
      'Basenji',
      'Beagle',
      'Belgian Malinois',
      'Boerboel',
      'Border Collie',
      'Boxer',
      'Bullmastiff',
      'Cane Corso',
      'Caucasian Shepherd',
      'Chihuahua',
      'Chow Chow',
      'Cocker Spaniel',
      'Dachshund',
      'Doberman Pinscher',
      'English Bulldog',
      'French Bulldog',
      'German Shepherd',
      'Golden Retriever',
      'Great Dane',
      'Jack Russell Terrier',
      'Labrador Retriever',
      'Lhasa Apso',
      'Local/Indigenous Dog',
      'Maltese',
      'Mixed Breed',
      'Neapolitan Mastiff',
      'Pekingese',
      'Pomeranian',
      'Poodle',
      'Rottweiler',
      'Samoyed',
      'Shih Tzu',
      'Siberian Husky',
      'Unknown/Not Specified',
      'Yorkshire Terrier',
      'Other Breed',
    ],
    'species_cat': [
      'Abyssinian',
      'Bengal',
      'Birman',
      'British Shorthair',
      'Burmese',
      'Domestic Longhair',
      'Domestic Medium Hair',
      'Domestic Shorthair',
      'Maine Coon',
      'Mixed Breed',
      'Norwegian Forest Cat',
      'Persian',
      'Ragdoll',
      'Russian Blue',
      'Siamese',
      'Sphynx',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_cattle': [
      'Adamawa Gudali',
      'Angus',
      'Brahman',
      'Brown Swiss',
      'Crossbred',
      'Holstein Friesian',
      'Indigenous/Local',
      'Jersey',
      'Muturu',
      "N'Dama",
      'Red Bororo / Rahaji',
      'Simmental',
      'Sokoto Gudali',
      'Unknown/Not Specified',
      'White Fulani / Bunaji',
      'Other Breed',
    ],
    'species_goat': [
      'Alpine',
      'Anglo-Nubian',
      'Boer',
      'Crossbred',
      'Indigenous/Local',
      'Red Sokoto / Maradi',
      'Saanen',
      'Sahel',
      'Toggenburg',
      'Unknown/Not Specified',
      'West African Dwarf',
      'Other Breed',
    ],
    'species_sheep': [
      'Balami',
      'Crossbred',
      'Dorper',
      'Indigenous/Local',
      'Merino',
      'Suffolk',
      'Uda',
      'Unknown/Not Specified',
      'West African Dwarf',
      'Yankasa',
      'Other Breed',
    ],
    'species_pig': [
      'Berkshire',
      'Crossbred',
      'Duroc',
      'Hampshire',
      'Indigenous/Local',
      'Landrace',
      'Large Black',
      'Large White',
      'Pietrain',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_rabbit': [
      'Angora',
      'Californian',
      'Chinchilla',
      'Crossbred',
      'Dutch',
      'Flemish Giant',
      'Indigenous/Local',
      'Lionhead',
      'New Zealand White',
      'Rex',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_chicken': [
      'Arbor Acres',
      'Cobb 500',
      'Cornish',
      'Crossbred',
      'Hy-Line Brown',
      'ISA Brown',
      'Indigenous/Local Chicken',
      'Lohmann Brown',
      'Noiler',
      'Plymouth Rock',
      'Rhode Island Red',
      'Ross 308',
      'Sussex',
      'Unknown/Not Specified',
      'White Leghorn',
      'Other Breed/Strain',
    ],
    'species_horse': [
      'American Quarter Horse',
      'Andalusian',
      'Arabian',
      'Crossbred',
      'Friesian',
      'Indigenous/Local',
      'Paint Horse',
      'Standardbred',
      'Thoroughbred',
      'Unknown/Not Specified',
      'Warmblood',
      'Other Breed',
    ],
    'species_donkey': [
      'African Wild-type/Local',
      'Crossbred',
      'Mammoth Jackstock',
      'Miniature Donkey',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_camel': [
      'Bactrian',
      'Crossbred',
      'Dromedary',
      'Indigenous/Local',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_guinea_pig': [
      'Abyssinian',
      'American',
      'Coronet',
      'Peruvian',
      'Silkie',
      'Teddy',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_hamster': [
      'Campbell Dwarf',
      'Chinese',
      'Roborovski',
      'Syrian',
      'Winter White Dwarf',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_ferret': [
      'Albino',
      'Black Sable',
      'Champagne',
      'Sable',
      'Unknown/Not Specified',
      'Other Variety',
    ],
    'species_turkey': [
      'Beltsville Small White',
      'Bourbon Red',
      'Broad Breasted White',
      'Bronze',
      'Indigenous/Local',
      'Unknown/Not Specified',
      'Other Breed/Strain',
    ],
    'species_duck': [
      'Aylesbury',
      'Indigenous/Local',
      'Khaki Campbell',
      'Mallard',
      'Muscovy',
      'Pekin',
      'Rouen',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_goose': [
      'African',
      'Chinese',
      'Embden',
      'Indigenous/Local',
      'Toulouse',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_guinea_fowl': [
      'Helmeted',
      'Lavender',
      'Pearl Grey',
      'White',
      'Unknown/Not Specified',
      'Other Variety',
    ],
    'species_quail': [
      'Bobwhite',
      'Button',
      'California',
      'Japanese/Coturnix',
      'Unknown/Not Specified',
      'Other Variety',
    ],
    'species_pigeon': [
      'Fantail',
      'Homing/Racing',
      'King',
      'Modena',
      'Pouters',
      'Tumblers',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_parrot': [
      'African Grey',
      'Amazon',
      'Budgerigar',
      'Cockatiel',
      'Cockatoo',
      'Lovebird',
      'Macaw',
      'Unknown/Not Specified',
      'Other Species/Variety',
    ],
    'species_canary_finch': [
      'Canary',
      'Gouldian Finch',
      'Society Finch',
      'Star Finch',
      'Zebra Finch',
      'Unknown/Not Specified',
      'Other Species/Variety',
    ],
    'species_tortoise': [
      'African Spurred/Sulcata',
      'Greek',
      "Hermann's",
      'Leopard',
      'Red-footed',
      'Unknown/Not Specified',
      'Other Species/Variety',
    ],
    'species_turtle': [
      'African Sideneck',
      'Box Turtle',
      'Painted Turtle',
      'Red-eared Slider',
      'Unknown/Not Specified',
      'Other Species/Variety',
    ],
    'species_snake': [
      'Ball Python',
      'Boa Constrictor',
      'Corn Snake',
      'Garter Snake',
      'Kingsnake',
      'Milk Snake',
      'Unknown/Not Specified',
      'Other Species/Morph',
    ],
    'species_lizard': [
      'African Fat-tailed Gecko',
      'Bearded Dragon',
      'Blue-tongued Skink',
      'Chameleon',
      'Crested Gecko',
      'Green Iguana',
      'Leopard Gecko',
      'Unknown/Not Specified',
      'Other Species/Morph',
    ],
    'species_fish': [
      'Betta',
      'Cichlid',
      'Goldfish',
      'Guppy',
      'Koi',
      'Molly',
      'Tilapia',
      'Unknown/Not Specified',
      'Other Species/Variety',
    ],
    'species_other_companion': ['Unknown/Not Specified', 'Other Breed/Variety'],
    'species_other_farm': [
      'Crossbred',
      'Indigenous/Local',
      'Unknown/Not Specified',
      'Other Breed/Variety',
    ],
    'species_other_bird': ['Unknown/Not Specified', 'Other Breed/Variety'],
    'species_other_exotic': ['Unknown/Not Specified', 'Other Breed/Variety'],
  };

  static final List<AnimalSpeciesOption> orderedSpecies = [...species]
    ..sort((a, b) {
      final category = a.category.index.compareTo(b.category.index);
      return category != 0 ? category : a.displayName.compareTo(b.displayName);
    });

  static final List<AnimalBreedOption> breeds = species
      .expand(
        (speciesOption) => _namesFor(speciesOption).map(
          (name) => AnimalBreedOption(
            id: 'breed_${speciesOption.id.substring('species_'.length)}_${_slug(name)}',
            speciesId: speciesOption.id,
            displayName: name,
            aliases: _breedAliases[name] ?? const [],
            allowsCustomBreed: name.startsWith('Other '),
            isUnknownOption: name.startsWith('Unknown'),
          ),
        ),
      )
      .toList(growable: false);

  static const Map<String, List<String>> _breedAliases = {
    'White Fulani / Bunaji': ['white fulani', 'bunaji'],
    'Red Bororo / Rahaji': ['red bororo', 'rahaji'],
    'Red Sokoto / Maradi': ['red sokoto', 'maradi'],
    'Domestic Shorthair': ['dsh', 'domestic short hair'],
    'German Shepherd': ['alsatian'],
  };

  static List<String> _namesFor(AnimalSpeciesOption option) {
    final configured = _breedNames[option.id];
    if (configured != null) return configured;
    return switch (option.category) {
      AnimalCategory.companion ||
      AnimalCategory.farm ||
      AnimalCategory.equine ||
      AnimalCategory.laboratoryAnimal => const [
        'Mixed/Crossbred',
        'Unknown/Not Specified',
        'Other Breed/Variety',
      ],
      AnimalCategory.birds || AnimalCategory.avian => const [
        'Unknown/Not Specified',
        'Other Breed/Strain/Variety',
      ],
      AnimalCategory.reptile => const [
        'Unknown Species/Morph',
        'Other Species/Morph',
      ],
      AnimalCategory.amphibian => const [
        'Unknown Species/Type',
        'Other Species/Type',
      ],
      AnimalCategory.aquatic => const [
        'Unknown Species/Variety',
        'Other Species/Variety',
      ],
      AnimalCategory.wildlife ||
      AnimalCategory.exotic ||
      AnimalCategory.other => const [
        'Unknown/Not Specified',
        'Other Species/Type',
      ],
    };
  }

  static String breedFieldLabel(AnimalSpeciesOption? option) {
    if (option == null) return 'Breed';
    return switch (option.category) {
      AnimalCategory.birds || AnimalCategory.avian => 'Breed / Strain',
      AnimalCategory.reptile => 'Species / Morph',
      AnimalCategory.aquatic => 'Species / Variety',
      AnimalCategory.amphibian ||
      AnimalCategory.wildlife ||
      AnimalCategory.exotic ||
      AnimalCategory.other => 'Type / Variety',
      _ => 'Breed',
    };
  }

  static AnimalSpeciesOption? speciesById(String? id) {
    for (final option in species) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// Resolves persisted legacy species text without rewriting the record.
  /// New registrations keep using stable ids in their controller state.
  static AnimalSpeciesOption? speciesForDisplayName(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final option in species) {
      if (option.displayName.toLowerCase() == normalized ||
          option.veterinaryName?.toLowerCase() == normalized ||
          option.searchAliases.any(
            (alias) => alias.toLowerCase() == normalized,
          )) {
        return option;
      }
    }
    return null;
  }

  static AnimalBreedOption? breedById(String? id) {
    for (final option in breeds) {
      if (option.id == id) return option;
    }
    return null;
  }

  static List<AnimalBreedOption> breedsFor(String speciesId) {
    final values = breeds
        .where((option) => option.speciesId == speciesId)
        .toList(growable: false);
    return [...values]..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  static List<String> validate() {
    final errors = <String>[];
    final speciesIds = <String>{};
    final breedIds = <String>{};
    for (final option in species) {
      if (!speciesIds.add(option.id)) {
        errors.add('Duplicate species ID: ${option.id}');
      }
      if (breedsFor(option.id).isEmpty) {
        errors.add('No breeds for ${option.id}');
      }
    }
    for (final option in breeds) {
      if (!breedIds.add(option.id)) {
        errors.add('Duplicate breed ID: ${option.id}');
      }
      if (!speciesIds.contains(option.speciesId)) {
        errors.add('Unknown species ${option.speciesId} for ${option.id}');
      }
    }
    return errors;
  }

  static String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
