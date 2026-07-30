import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/config/animal_registration_provider.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/models/animal_catalogue.dart';
import 'package:avera/core/repositories/clinic_repository.dart';

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
    expect(controller.state.resolvedBreedName, 'Lhasa Apso');

    controller.selectSpecies('species_cat');

    expect(controller.state.selectedBreedId, isNull);
    expect(controller.state.availableBreeds, isNotEmpty);
    expect(
      controller.state.availableBreeds.map((item) => item.displayName),
      isNot(contains('Lhasa Apso')),
    );
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
        animal: const AnimalsCompanion(
          animalName: Value('Catalogue Test Patient'),
          species: Value('Cat'),
          breed: Value('Lhasa Apso'),
        ),
      ),
      throwsArgumentError,
    );
  });
}
