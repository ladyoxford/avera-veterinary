import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/config/animal_registration_provider.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/models/animal_catalogue.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/services/animal_age_service.dart';

void main() {
  test('catalogue has unique IDs and breeds for every species', () {
    expect(AnimalCatalogue.validate(), isEmpty);
    expect(
      AnimalCatalogue.species.map((item) => item.id).toSet().length,
      AnimalCatalogue.species.length,
    );
    expect(
      AnimalCatalogue.breeds.map((item) => item.id).toSet().length,
      AnimalCatalogue.breeds.length,
    );
    for (final species in AnimalCatalogue.species) {
      expect(
        AnimalCatalogue.breedsFor(species.id),
        isNotEmpty,
        reason: species.displayName,
      );
    }
  });

  test('catalogue uses clinical breed and coat terminology correctly', () {
    final catBreeds = AnimalCatalogue.breedsFor(
      'species_cat',
    ).map((item) => item.displayName).toSet();
    expect(catBreeds, contains('Domestic Shorthair'));
    expect(catBreeds, isNot(contains('Ginger Shorthair')));
    expect(
      AnimalCatalogue.breedsFor('species_dog').map((item) => item.displayName),
      contains('Lhasa Apso'),
    );
    expect(
      AnimalCatalogue.breedsFor('species_goat').map((item) => item.displayName),
      contains('West African Dwarf'),
    );
  });

  test('global dog search finds both Eskimo breeds', () {
    final results = AnimalCatalogue.searchBreeds(
      'species_dog',
      'eski',
    ).map((breed) => breed.displayName);

    expect(
      results,
      containsAll(['American Eskimo Dog', 'Canadian Eskimo Dog']),
    );
  });

  test('global horse search includes Argentine breeds', () {
    final results = AnimalCatalogue.searchBreeds(
      'species_horse',
      'argentine',
    ).map((breed) => breed.displayName);

    expect(
      results,
      containsAll([
        'Argentine Criollo / Criollo Argentino',
        'Argentine Polo Pony',
      ]),
    );
  });

  test('aliases resolve to one canonical breed', () {
    expect(
      AnimalCatalogue.resolveBreed('species_dog', 'Alsatian')?.displayName,
      'German Shepherd Dog',
    );
    expect(
      AnimalCatalogue.resolveBreed('species_goat', 'Maradi')?.displayName,
      'Red Sokoto / Maradi',
    );
    expect(
      AnimalCatalogue.resolveBreed('species_cattle', 'Holstein')?.displayName,
      'Holstein Friesian',
    );
    expect(
      AnimalCatalogue.resolveBreed(
        'species_horse',
        'Criollo Horse',
      )?.displayName,
      'Argentine Criollo / Criollo Argentino',
    );
  });

  test('search is case-insensitive and punctuation tolerant', () {
    expect(
      AnimalCatalogue.searchBreeds(
        'species_cattle',
        'HOLSTEIN-FRIESIAN',
      ).map((breed) => breed.displayName),
      contains('Holstein Friesian'),
    );
    expect(
      AnimalCatalogue.searchBreeds(
        'species_goat',
        'tennessee fainting',
      ).map((breed) => breed.displayName),
      contains('Myotonic / Tennessee Fainting Goat'),
    );
  });

  test('representative global breeds exist for major species', () {
    expect(_breedNames('species_dog').length, greaterThanOrEqualTo(95));
    expect(_breedNames('species_horse').length, greaterThanOrEqualTo(40));
    expect(_breedNames('species_cat').length, greaterThanOrEqualTo(35));
    expect(_breedNames('species_cattle').length, greaterThanOrEqualTo(35));
    expect(_breedNames('species_goat').length, greaterThanOrEqualTo(25));
    expect(_breedNames('species_sheep').length, greaterThanOrEqualTo(25));
    expect(_breedNames('species_pig').length, greaterThanOrEqualTo(17));
    expect(_breedNames('species_rabbit').length, greaterThanOrEqualTo(15));
    expect(_breedNames('species_chicken').length, greaterThanOrEqualTo(25));

    expect(_breedNames('species_cat'), contains('Egyptian Mau'));
    expect(_breedNames('species_cattle'), contains('White Fulani / Bunaji'));
    expect(_breedNames('species_goat'), contains('Damascus / Shami'));
    expect(_breedNames('species_sheep'), contains('Ile de France'));
    expect(_breedNames('species_pig'), contains('Mangalitsa'));
    expect(_breedNames('species_rabbit'), contains('Holland Lop'));
    expect(_breedNames('species_chicken'), contains('FUNAAB Alpha'));
    expect(_breedNames('species_turkey'), contains('Royal Palm'));
    expect(_breedNames('species_duck'), contains('Khaki Campbell'));
    expect(_breedNames('species_goose'), contains('Toulouse'));
    expect(_breedNames('species_guinea_fowl'), contains('Vulturine'));
    expect(_breedNames('species_quail'), contains('Jumbo Coturnix'));
  });

  test('breed filtering never crosses species', () {
    final dogResults = AnimalCatalogue.searchBreeds('species_dog', 'eskimo');
    expect(dogResults, isNotEmpty);
    expect(
      dogResults.every((breed) => breed.speciesId == 'species_dog'),
      isTrue,
    );
    expect(AnimalCatalogue.searchBreeds('species_goat', 'eskimo'), isEmpty);
    expect(
      AnimalCatalogue.breedsForSpecies(
        'species_horse',
      ).every((breed) => breed.speciesId == 'species_horse'),
      isTrue,
    );
  });

  test('renamed display labels preserve historical breed IDs', () {
    expect(
      AnimalCatalogue.breedById('breed_dog_german_shepherd')?.displayName,
      'German Shepherd Dog',
    );
    expect(
      AnimalCatalogue.breedById('breed_dog_poodle')?.displayName,
      'Standard Poodle',
    );
    expect(
      AnimalCatalogue.breedById(
        'breed_horse_american_quarter_horse',
      )?.displayName,
      'Quarter Horse',
    );
    expect(
      AnimalCatalogue.breedById('breed_horse_warmblood')?.displayName,
      'Warmblood',
    );
    expect(
      AnimalCatalogue.breedById('breed_pig_large_white')?.displayName,
      'Large White / Yorkshire',
    );
  });

  test('custom farm breed values round-trip with their species', () {
    final id = AnimalCatalogue.customBreedId(
      speciesId: 'species_horse',
      name: 'Pampas Working Horse: Local Line',
    );

    expect(AnimalCatalogue.isCustomBreedId(id), isTrue);
    expect(
      AnimalCatalogue.customBreedName(id),
      'Pampas Working Horse: Local Line',
    );
    expect(
      AnimalCatalogue.breedDisplayName(id),
      'Pampas Working Horse: Local Line',
    );
    expect(AnimalCatalogue.breedBelongsToSpecies(id, 'species_horse'), isTrue);
    expect(AnimalCatalogue.breedBelongsToSpecies(id, 'species_dog'), isFalse);
  });

  test('expanded species catalogue supports categories and aliases', () {
    expect(AnimalCatalogue.species.length, greaterThanOrEqualTo(80));
    expect(
      AnimalCatalogue.species.map((item) => item.category).toSet(),
      containsAll(AnimalCategory.values),
    );
    expect(
      AnimalCatalogue.species
          .where((option) => option.searchableText.contains('canine'))
          .map((option) => option.id),
      contains('species_dog'),
    );
    expect(
      AnimalCatalogue.species
          .where((option) => option.searchableText.contains('bovine'))
          .map((option) => option.id),
      contains('species_cattle'),
    );
    expect(
      AnimalCatalogue.species
          .where((option) => option.searchableText.contains('caprine'))
          .map((option) => option.id),
      contains('species_goat'),
    );
  });

  test('every species has unknown and custom fallback options', () {
    for (final species in AnimalCatalogue.species) {
      final options = AnimalCatalogue.breedsFor(species.id);
      expect(
        options.any((option) => option.isUnknownOption),
        isTrue,
        reason: '${species.displayName} needs an unknown option',
      );
      expect(
        options.any((option) => option.allowsCustomBreed),
        isTrue,
        reason: '${species.displayName} needs a custom option',
      );
    }
  });

  test('changing species clears an incompatible breed only', () {
    final controller = AnimalRegistrationSelectionController();
    addTearDown(controller.dispose);
    controller.selectSpecies('species_dog');
    controller.selectBreed('breed_dog_lhasa_apso');
    controller.setAgeInputMode(AnimalAgeInputMode.dateOfBirth);
    controller.setAgeUnit(AnimalAgeUnit.years);
    controller.setDateOfBirth(DateTime(2020, 6, 15));
    expect(controller.state.resolvedBreedName, 'Lhasa Apso');

    controller.selectSpecies('species_cat');

    expect(controller.state.selectedBreedId, isNull);
    expect(controller.state.availableBreeds, isNotEmpty);
    expect(
      controller.state.availableBreeds.map((item) => item.displayName),
      isNot(contains('Lhasa Apso')),
    );
    expect(controller.state.ageInputMode, AnimalAgeInputMode.dateOfBirth);
    expect(controller.state.ageUnit, AnimalAgeUnit.years);
    expect(controller.state.dateOfBirth, DateTime(2020, 6, 15));
  });

  test('custom species and breed require controlled values', () {
    final controller = AnimalRegistrationSelectionController();
    addTearDown(controller.dispose);
    controller.selectSpecies('species_other_exotic');
    controller.selectBreed('breed_other_exotic_other_breed_variety');
    expect(controller.validate(), isFalse);
    controller.setCustomSpecies('Axolotl');
    controller.setCustomBreed('Leucistic');
    expect(controller.validate(), isTrue);
    expect(controller.state.resolvedSpeciesName, 'Axolotl');
    expect(controller.state.resolvedBreedName, 'Leucistic');
  });

  test('repository rejects an incompatible canonical pair', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );

    expect(
      repository.registerAnimalWithHospitalNumber(
        session: session!,
        submissionId: 'invalid-species-breed-pair',
        speciesId: 'species_cat',
        breedId: 'breed_dog_lhasa_apso',
        owner: OwnersCompanion.insert(
          fullName: 'Catalogue Test Owner',
          phone: '08000000001',
        ),
        animal: AnimalsCompanion(
          animalName: const Value('Catalogue Test Patient'),
          species: const Value('Cat'),
          breed: const Value('Lhasa Apso'),
          dateOfBirth: Value(DateTime(2025, 1, 1)),
        ),
      ),
      throwsArgumentError,
    );
  });
}

Set<String> _breedNames(String speciesId) => AnimalCatalogue.breedsForSpecies(
  speciesId,
).map((breed) => breed.displayName).toSet();
