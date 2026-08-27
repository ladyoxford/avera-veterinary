String normalizeAnimalCatalogueSearch(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

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

  String get searchableText => normalizeAnimalCatalogueSearch(
    '$displayName ${veterinaryName ?? ''} ${searchAliases.join(' ')}',
  );
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
      normalizeAnimalCatalogueSearch('$displayName ${aliases.join(' ')}');
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
      'Affenpinscher',
      'Afghan Hound',
      'Airedale Terrier',
      'Akita',
      'Alaskan Malamute',
      'American Bulldog',
      'American Cocker Spaniel',
      'American Eskimo Dog',
      'American Foxhound',
      'American Pit Bull Terrier',
      'American Staffordshire Terrier',
      'Anatolian Shepherd Dog',
      'Australian Cattle Dog',
      'Australian Shepherd',
      'Basenji',
      'Basset Hound',
      'Beagle',
      'Belgian Malinois',
      'Belgian Sheepdog / Groenendael',
      'Belgian Tervuren',
      'Bernese Mountain Dog',
      'Bichon Frise',
      'Bloodhound',
      'Boerboel',
      'Border Collie',
      'Borzoi',
      'Boston Terrier',
      'Boxer',
      'Brittany',
      'Bull Terrier',
      'Bullmastiff',
      'Canadian Eskimo Dog',
      'Cane Corso',
      'Caucasian Shepherd Dog',
      'Cavalier King Charles Spaniel',
      'Central Asian Shepherd Dog',
      'Chesapeake Bay Retriever',
      'Chihuahua',
      'Chinese Crested',
      'Chow Chow',
      'Cocker Spaniel',
      'Dachshund',
      'Dalmatian',
      'Doberman Pinscher',
      'Dutch Shepherd',
      'English Bulldog',
      'English Cocker Spaniel',
      'English Mastiff',
      'English Setter',
      'English Springer Spaniel',
      'Flat-Coated Retriever',
      'French Bulldog',
      'German Shepherd Dog',
      'German Shorthaired Pointer',
      'German Wirehaired Pointer',
      'Giant Schnauzer',
      'Golden Retriever',
      'Gordon Setter',
      'Great Dane',
      'Great Pyrenees',
      'Greyhound',
      'Havanese',
      'Irish Setter',
      'Irish Wolfhound',
      'Jack Russell Terrier',
      'Kangal Shepherd Dog',
      'Labrador Retriever',
      'Leonberger',
      'Lhasa Apso',
      'Local/Indigenous Dog',
      'Maltese',
      'Miniature Bull Terrier',
      'Miniature Pinscher',
      'Miniature Poodle',
      'Miniature Schnauzer',
      'Mixed Breed',
      'Neapolitan Mastiff',
      'Newfoundland',
      'Nova Scotia Duck Tolling Retriever',
      'Old English Sheepdog',
      'Papillon',
      'Parson Russell Terrier',
      'Pekingese',
      'Pembroke Welsh Corgi',
      'Pointer',
      'Pomeranian',
      'Portuguese Water Dog',
      'Pug',
      'Rhodesian Ridgeback',
      'Rough Collie',
      'Rottweiler',
      'Saint Bernard',
      'Samoyed',
      'Saluki',
      'Scottish Deerhound',
      'Scottish Terrier',
      'Shar Pei',
      'Shetland Sheepdog',
      'Shih Tzu',
      'Shiba Inu',
      'Siberian Husky',
      'Smooth Collie',
      'Staffordshire Bull Terrier',
      'Standard Poodle',
      'Standard Schnauzer',
      'Tibetan Mastiff',
      'Toy Poodle',
      'Unknown/Not Specified',
      'Vizsla',
      'Weimaraner',
      'West Highland White Terrier',
      'Whippet',
      'Yorkshire Terrier',
      'Other Breed',
    ],
    'species_cat': [
      'Abyssinian',
      'American Shorthair',
      'Balinese',
      'Bengal',
      'Birman',
      'Bombay',
      'British Longhair',
      'British Shorthair',
      'Burmese',
      'Chartreux',
      'Cornish Rex',
      'Devon Rex',
      'Domestic Longhair',
      'Domestic Medium Hair',
      'Domestic Shorthair',
      'Egyptian Mau',
      'Exotic Shorthair',
      'Himalayan',
      'Maine Coon',
      'Manx',
      'Mixed Breed',
      'Norwegian Forest Cat',
      'Ocicat',
      'Oriental Shorthair',
      'Persian',
      'Ragdoll',
      'Russian Blue',
      'Savannah',
      'Scottish Fold',
      'Selkirk Rex',
      'Siamese',
      'Siberian',
      'Somali',
      'Sphynx',
      'Tonkinese',
      'Turkish Angora',
      'Turkish Van',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_cattle': [
      'Adamawa Gudali',
      'Afrikaner',
      'Angus',
      'Ankole-Watusi',
      'Ayrshire',
      'Beefmaster',
      'Belgian Blue',
      'Bonsmara',
      'Brahman',
      'Brangus',
      'Brown Swiss',
      'Charolais',
      'Crossbred',
      'Dexter',
      'Gir / Gyr',
      'Guernsey',
      'Hereford',
      'Highland',
      'Holstein Friesian',
      'Indigenous/Local',
      'Jersey',
      'Keteku',
      'Kuri',
      'Limousin',
      'Muturu',
      "N'Dama",
      'Nelore',
      'Red Bororo / Rahaji',
      'Red Angus',
      'Red Sindhi',
      'Sahiwal',
      'Santa Gertrudis',
      'Shorthorn',
      'Simmental',
      'Sokoto Gudali',
      'Unknown/Not Specified',
      'Wadara',
      'White Fulani / Bunaji',
      'Other Breed',
    ],
    'species_goat': [
      'Alpine',
      'Anglo-Nubian / Nubian',
      'Angora',
      'Barbari',
      'Beetal',
      'Black Bengal',
      'Boer',
      'Cashmere',
      'Crossbred',
      'Damascus / Shami',
      'French Alpine',
      'Indigenous/Local',
      'Jamunapari',
      'Kalahari Red',
      'Kiko',
      'LaMancha',
      'Myotonic / Tennessee Fainting Goat',
      'Oberhasli',
      'Red Sokoto / Maradi',
      'Saanen',
      'Sahel',
      'Savanna',
      'Spanish Goat',
      'Toggenburg',
      'Unknown/Not Specified',
      'West African Dwarf',
      'Other Breed',
    ],
    'species_sheep': [
      'Awassi',
      'Balami',
      'Blackhead Persian',
      'Charollais',
      'Cheviot',
      'Corriedale',
      'Crossbred',
      'Damara',
      'Dohne Merino',
      'Dorper',
      'Dorset',
      'East Friesian',
      'Hampshire',
      'Indigenous/Local',
      'Ile de France',
      'Katahdin',
      'Lacaune',
      'Merino',
      'Rambouillet',
      'Romanov',
      'Southdown',
      'Suffolk',
      'Texel',
      'Uda',
      'Unknown/Not Specified',
      'West African Dwarf',
      'White Dorper',
      'Yankasa',
      'Other Breed',
    ],
    'species_pig': [
      'Berkshire',
      'Chester White',
      'Crossbred',
      'Duroc',
      'Gloucestershire Old Spots',
      'Hampshire',
      'Hereford Pig',
      'Indigenous/Local',
      'Landrace',
      'Large Black',
      'Large White / Yorkshire',
      'Mangalitsa',
      'Meishan',
      'Pietrain',
      'Poland China',
      'Spotted',
      'Tamworth',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_rabbit': [
      'Angora',
      'Californian',
      'Chinchilla',
      'Crossbred',
      'Dutch',
      'English Lop',
      'Flemish Giant',
      'French Lop',
      'Holland Lop',
      'Indigenous/Local',
      'Lionhead',
      'Mini Rex',
      'Netherland Dwarf',
      'New Zealand White',
      'Rex',
      'Silver Fox',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_chicken': [
      'Arbor Acres',
      'Australorp',
      'Bovans Brown',
      'Bovans White',
      'Brahma',
      'Cobb 500',
      'Cochin',
      'Cornish',
      'Crossbred',
      'Dekalb White',
      'FUNAAB Alpha',
      'Hubbard',
      'Hy-Line Brown',
      'Hy-Line W-36',
      'ISA Brown',
      'Indigenous/Local Chicken',
      'Leghorn',
      'Lohmann Brown',
      'Lohmann LSL',
      'Noiler',
      'Orpington',
      'Plymouth Rock',
      'Rhode Island Red',
      'Ross 308',
      'Shaver Brown',
      'Sussex',
      'Unknown/Not Specified',
      'Other Breed/Strain',
    ],
    'species_horse': [
      'Akhal-Teke',
      'American Saddlebred',
      'Andalusian',
      'Appaloosa',
      'Arabian',
      'Argentine Criollo / Criollo Argentino',
      'Argentine Polo Pony',
      'Belgian Draft',
      'Campolina',
      'Clydesdale',
      'Connemara Pony',
      'Crossbred',
      'Dutch Warmblood',
      'Fjord Horse',
      'Friesian',
      'Gypsy Vanner / Irish Cob',
      'Haflinger',
      'Hanoverian',
      'Holsteiner',
      'Icelandic Horse',
      'Indigenous/Local',
      'Kathiawari',
      'Lipizzaner',
      'Lusitano',
      'Mangalarga Marchador',
      'Marwari',
      'Missouri Fox Trotter',
      'Morgan',
      'Mustang',
      'Oldenburg',
      'Paint Horse',
      'Paso Fino',
      'Percheron',
      'Peruvian Paso',
      'Quarter Horse',
      'Rocky Mountain Horse',
      'Selle Francais',
      'Shetland Pony',
      'Shire',
      'Standardbred',
      'Tennessee Walking Horse',
      'Thoroughbred',
      'Trakehner',
      'Warmblood',
      'Unknown/Not Specified',
      'Welsh Pony',
      'Westphalian',
      'Other Breed',
    ],
    'species_donkey': [
      'African Wild-type/Local',
      'American Mammoth Jackstock',
      'Andalusian Donkey',
      'Asinara Donkey',
      'Crossbred',
      'Grand Noir du Berry',
      'Miniature Donkey',
      'Poitou Donkey',
      'Somali Wild Ass',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_mule': [
      'Draft Mule',
      'Hinny',
      'Mammoth Mule',
      'Miniature Mule',
      'Pack Mule',
      'Riding Mule',
      'Unknown/Not Specified',
      'Other Type',
    ],
    'species_camel': [
      'Bactrian',
      'Crossbred',
      'Dromedary',
      'Indigenous/Local',
      'Kharai',
      'Majaheem',
      'Rajasthani',
      'Somali Camel',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_llama': [
      'Ccara Llama',
      'Classic Llama',
      'Suri Llama',
      'Tapada Llama',
      'Woolly Llama',
      'Unknown/Not Specified',
      'Other Type',
    ],
    'species_alpaca': [
      'Huacaya Alpaca',
      'Suri Alpaca',
      'Unknown/Not Specified',
      'Other Type',
    ],
    'species_guinea_pig': [
      'Abyssinian',
      'American',
      'Baldwin',
      'Coronet',
      'English Crested',
      'Lunkarya',
      'Peruvian',
      'Rex',
      'Skinny Pig',
      'Silkie',
      'Teddy',
      'Texel',
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
      'Chocolate',
      'Cinnamon',
      'Dark-eyed White',
      'Panda',
      'Sable',
      'Silver',
      'Unknown/Not Specified',
      'Other Variety',
    ],
    'species_turkey': [
      'Beltsville Small White',
      'Black Spanish',
      'Blue Slate',
      'Bourbon Red',
      'Broad Breasted Bronze',
      'Broad Breasted White',
      'Bronze',
      'Jersey Buff',
      'Indigenous/Local',
      'Narragansett',
      'Royal Palm',
      'White Holland',
      'Unknown/Not Specified',
      'Other Breed/Strain',
    ],
    'species_duck': [
      'Ancona',
      'Appleyard',
      'Aylesbury',
      'Cayuga',
      'Indian Runner',
      'Indigenous/Local',
      'Khaki Campbell',
      'Mallard',
      'Moulard',
      'Muscovy',
      'Pekin',
      'Rouen',
      'Welsh Harlequin',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_goose': [
      'African',
      'American Buff',
      'Chinese',
      'Embden',
      'Egyptian',
      'Indigenous/Local',
      'Pilgrim',
      'Roman Tufted',
      'Sebastopol',
      'Swan Goose',
      'Toulouse',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_guinea_fowl': [
      'Buff Dundotte',
      'French Guinea Fowl',
      'Helmeted',
      'Lavender',
      'Pied',
      'Pearl Grey',
      'Royal Purple',
      'Vulturine',
      'White',
      'Unknown/Not Specified',
      'Other Variety',
    ],
    'species_quail': [
      'Bobwhite',
      'Button',
      'California',
      'Gambel',
      'Italian',
      'Japanese/Coturnix',
      'Jumbo Coturnix',
      'Manchurian Golden',
      'Pharaoh Coturnix',
      'Texas A&M',
      'Unknown/Not Specified',
      'Other Variety',
    ],
    'species_pigeon': [
      'Carneau',
      'Fantail',
      'Frillback',
      'Homing/Racing',
      'Jacobin',
      'King',
      'Modena',
      'Pouters',
      'Roller',
      'Tumblers',
      'Unknown/Not Specified',
      'Other Breed',
    ],
    'species_parrot': [
      'African Grey',
      'Amazon',
      'Budgerigar',
      'Caique',
      'Cockatiel',
      'Cockatoo',
      'Conure',
      'Eclectus',
      'Indian Ringneck',
      'Lorikeet',
      'Lovebird',
      'Macaw',
      'Parrotlet',
      'Senegal Parrot',
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
            id: _breedIdFor(speciesOption.id, name),
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
    'American Eskimo Dog': ['American Eskimo', 'Eskimo Dog'],
    'Argentine Criollo / Criollo Argentino': [
      'Argentine Criollo',
      'Argentinian Criollo',
      'Criollo Argentino',
      'Criollo Horse',
    ],
    'American Mammoth Jackstock': ['Mammoth Jackstock'],
    'Anglo-Nubian / Nubian': ['Anglo-Nubian', 'Nubian'],
    'Belgian Sheepdog / Groenendael': ['Belgian Sheepdog', 'Groenendael'],
    'Canadian Eskimo Dog': ['Canadian Inuit Dog', 'Canadian Eskimo'],
    'Caucasian Shepherd Dog': ['Caucasian Shepherd', 'Caucasian Ovcharka'],
    'Damascus / Shami': ['Damascus', 'Shami'],
    'Domestic Shorthair': ['DSH', 'Domestic Short Hair'],
    'German Shepherd Dog': ['German Shepherd', 'Alsatian'],
    'Gir / Gyr': ['Gir', 'Gyr'],
    'Great Pyrenees': ['Pyrenean Mountain Dog'],
    'Gypsy Vanner / Irish Cob': ['Gypsy Vanner', 'Irish Cob'],
    'Holstein Friesian': ['Holstein', 'Friesian', 'Holstein-Friesian'],
    'Japanese/Coturnix': ['Japanese Quail', 'Coturnix Quail'],
    'Large White / Yorkshire': ['Large White', 'Yorkshire Pig'],
    'Leghorn': ['White Leghorn'],
    'Myotonic / Tennessee Fainting Goat': [
      'Myotonic',
      'Tennessee Fainting Goat',
      'Fainting Goat',
    ],
    'Quarter Horse': ['American Quarter Horse'],
    'Red Bororo / Rahaji': ['Red Bororo', 'Rahaji'],
    'Red Sokoto / Maradi': ['Red Sokoto', 'Maradi'],
    'Standard Poodle': ['Poodle', 'Poodle - Standard'],
    'White Fulani / Bunaji': ['White Fulani', 'Bunaji'],
  };

  /// Display names have improved over time, but these persisted IDs must not
  /// change because existing patient and farm records already reference them.
  static const Map<String, String> _legacyBreedIdSlugs = {
    'species_dog|Caucasian Shepherd Dog': 'caucasian_shepherd',
    'species_dog|German Shepherd Dog': 'german_shepherd',
    'species_dog|Standard Poodle': 'poodle',
    'species_donkey|American Mammoth Jackstock': 'mammoth_jackstock',
    'species_goat|Anglo-Nubian / Nubian': 'anglo_nubian',
    'species_horse|Quarter Horse': 'american_quarter_horse',
    'species_pig|Large White / Yorkshire': 'large_white',
    'species_chicken|Leghorn': 'white_leghorn',
  };

  static const String _customBreedPrefix = 'custom_breed:';

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
  static AnimalSpeciesOption? speciesForDisplayName(String? value) =>
      resolveSpecies(value);

  static List<AnimalSpeciesOption> allSpecies() =>
      List.unmodifiable(orderedSpecies);

  static List<AnimalSpeciesOption> searchSpecies(String query) {
    final normalized = normalizeAnimalCatalogueSearch(query);
    if (normalized.isEmpty) return allSpecies();
    return orderedSpecies
        .where((option) => option.searchableText.contains(normalized))
        .toList(growable: false);
  }

  static AnimalSpeciesOption? resolveSpecies(String? value) {
    final byId = speciesById(value);
    if (byId != null) return byId;
    final normalized = normalizeAnimalCatalogueSearch(value ?? '');
    if (normalized.isEmpty) return null;
    for (final option in species) {
      if (normalizeAnimalCatalogueSearch(option.displayName) == normalized ||
          normalizeAnimalCatalogueSearch(option.veterinaryName ?? '') ==
              normalized ||
          option.searchAliases.any(
            (alias) => normalizeAnimalCatalogueSearch(alias) == normalized,
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
    final custom = _decodeCustomBreed(id);
    if (custom != null) {
      return AnimalBreedOption(
        id: id!,
        speciesId: custom.$1,
        displayName: custom.$2,
        allowsCustomBreed: true,
      );
    }
    return null;
  }

  static List<AnimalBreedOption> breedsFor(String speciesId) {
    final values = breeds
        .where((option) => option.speciesId == speciesId)
        .toList(growable: false);
    return [...values]..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  static List<AnimalBreedOption> breedsForSpecies(String speciesId) =>
      breedsFor(speciesId);

  static List<AnimalBreedOption> searchBreeds(String speciesId, String query) {
    final normalized = normalizeAnimalCatalogueSearch(query);
    final compatible = breedsFor(speciesId);
    if (normalized.isEmpty) return compatible;
    return compatible
        .where((option) => option.searchableText.contains(normalized))
        .toList(growable: false);
  }

  static AnimalBreedOption? resolveBreed(String speciesId, String? value) {
    final byId = breedById(value);
    if (byId != null && byId.speciesId == speciesId) return byId;
    final normalized = normalizeAnimalCatalogueSearch(value ?? '');
    if (normalized.isEmpty) return null;
    for (final option in breedsFor(speciesId)) {
      if (normalizeAnimalCatalogueSearch(option.displayName) == normalized ||
          option.aliases.any(
            (alias) => normalizeAnimalCatalogueSearch(alias) == normalized,
          )) {
        return option;
      }
    }
    return null;
  }

  static AnimalBreedOption? resolveLegacyBreed(
    String speciesId,
    String? value,
  ) => resolveBreed(speciesId, value);

  static String customBreedId({
    required String speciesId,
    required String name,
  }) {
    final normalizedName = name.trim();
    if (speciesById(speciesId) == null ||
        normalizedName.isEmpty ||
        normalizedName.length > 80) {
      throw ArgumentError(
        'A valid species and custom breed name are required.',
      );
    }
    return '$_customBreedPrefix$speciesId:$normalizedName';
  }

  static bool isCustomBreedId(String? value) =>
      value?.startsWith(_customBreedPrefix) == true;

  static String? customBreedName(String? value) =>
      _decodeCustomBreed(value)?.$2;

  static String breedDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Not recorded';
    return breedById(value)?.displayName ?? value;
  }

  static bool breedBelongsToSpecies(String? breedId, String speciesId) =>
      breedById(breedId)?.speciesId == speciesId;

  static List<String> validate() {
    final errors = <String>[];
    final speciesIds = <String>{};
    final breedIds = <String>{};
    final breedNamesBySpecies = <String, Set<String>>{};
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
      final names = breedNamesBySpecies.putIfAbsent(
        option.speciesId,
        () => <String>{},
      );
      if (!names.add(normalizeAnimalCatalogueSearch(option.displayName))) {
        errors.add(
          'Duplicate breed name ${option.displayName} for ${option.speciesId}',
        );
      }
    }
    return errors;
  }

  static String _breedIdFor(String speciesId, String name) {
    final speciesSlug = speciesId.substring('species_'.length);
    final breedSlug = _legacyBreedIdSlugs['$speciesId|$name'] ?? _slug(name);
    return 'breed_${speciesSlug}_$breedSlug';
  }

  static (String, String)? _decodeCustomBreed(String? value) {
    if (!isCustomBreedId(value)) return null;
    final encoded = value!.substring(_customBreedPrefix.length);
    final separator = encoded.indexOf(':');
    if (separator <= 0 || separator == encoded.length - 1) return null;
    final speciesId = encoded.substring(0, separator);
    final name = encoded.substring(separator + 1).trim();
    if (speciesById(speciesId) == null || name.isEmpty) return null;
    return (speciesId, name);
  }

  static String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
