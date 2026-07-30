import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/models/animal_catalogue.dart';
import 'package:avera/core/models/vaccine_catalogue.dart';

void main() {
  test('goat and sheep keep distinct species identities', () {
    expect(AnimalCatalogue.speciesById('species_goat')?.displayName, 'Goat');
    expect(AnimalCatalogue.speciesById('species_sheep')?.displayName, 'Sheep');
    expect(
      AnimalCatalogue.speciesById('species_goat')?.id,
      isNot(AnimalCatalogue.speciesById('species_sheep')?.id),
    );
  });

  test('PPR and Orf are not cattle vaccination protocols', () {
    final cattle = VaccineCatalogue.forSpecies('species_cattle');
    expect(cattle.map((protocol) => protocol.name), contains('CBPP'));
    expect(cattle.map((protocol) => protocol.name), isNot(contains('PPR')));
    expect(cattle.map((protocol) => protocol.name), isNot(contains('Orf')));
  });

  test('species vaccine compatibility prevents cross-species protocol use', () {
    expect(
      VaccineCatalogue.isCompatible(
        speciesId: 'species_dog',
        vaccineName: 'DHLPP',
      ),
      isTrue,
    );
    expect(
      VaccineCatalogue.isCompatible(
        speciesId: 'species_parrot',
        vaccineName: 'DHLPP',
      ),
      isFalse,
    );
    expect(
      VaccineCatalogue.isCompatible(
        speciesId: 'species_goat',
        vaccineName: 'PPR',
      ),
      isTrue,
    );
  });

  test(
    'protocol due-date suggestion is derived from the selected protocol',
    () {
      final protocol = VaccineCatalogue.byId('vax_dog_dhlpp')!;
      expect(
        protocol.suggestedDueDate(DateTime(2026, 7, 1)),
        DateTime(2026, 7, 29),
      );
    },
  );
}
