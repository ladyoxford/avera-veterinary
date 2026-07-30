import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/animal_catalogue.dart';

class AnimalRegistrationSelectionState {
  const AnimalRegistrationSelectionState({
    this.selectedSpeciesId,
    this.selectedBreedId,
    this.customSpeciesName = '',
    this.customBreedName = '',
    this.speciesValidationError,
    this.breedValidationError,
  });

  final String? selectedSpeciesId;
  final String? selectedBreedId;
  final String customSpeciesName;
  final String customBreedName;
  final String? speciesValidationError;
  final String? breedValidationError;

  AnimalSpeciesOption? get selectedSpecies =>
      AnimalCatalogue.speciesById(selectedSpeciesId);
  AnimalBreedOption? get selectedBreed =>
      AnimalCatalogue.breedById(selectedBreedId);
  List<AnimalBreedOption> get availableBreeds => selectedSpeciesId == null
      ? const []
      : AnimalCatalogue.breedsFor(selectedSpeciesId!);
  bool get requiresCustomSpecies =>
      selectedSpecies?.allowsCustomSpecies ?? false;
  bool get requiresCustomBreed => selectedBreed?.allowsCustomBreed ?? false;

  String? get resolvedSpeciesName {
    if (selectedSpecies == null) return null;
    return requiresCustomSpecies
        ? customSpeciesName.trim()
        : selectedSpecies!.displayName;
  }

  String? get resolvedBreedName {
    if (selectedBreed == null) return null;
    return requiresCustomBreed
        ? customBreedName.trim()
        : selectedBreed!.displayName;
  }

  AnimalRegistrationSelectionState copyWith({
    String? selectedSpeciesId,
    bool clearSpecies = false,
    String? selectedBreedId,
    bool clearBreed = false,
    String? customSpeciesName,
    String? customBreedName,
    String? speciesValidationError,
    bool clearSpeciesError = false,
    String? breedValidationError,
    bool clearBreedError = false,
  }) => AnimalRegistrationSelectionState(
    selectedSpeciesId: clearSpecies
        ? null
        : selectedSpeciesId ?? this.selectedSpeciesId,
    selectedBreedId: clearBreed
        ? null
        : selectedBreedId ?? this.selectedBreedId,
    customSpeciesName: customSpeciesName ?? this.customSpeciesName,
    customBreedName: customBreedName ?? this.customBreedName,
    speciesValidationError: clearSpeciesError
        ? null
        : speciesValidationError ?? this.speciesValidationError,
    breedValidationError: clearBreedError
        ? null
        : breedValidationError ?? this.breedValidationError,
  );
}

class AnimalRegistrationSelectionController
    extends StateNotifier<AnimalRegistrationSelectionState> {
  AnimalRegistrationSelectionController()
    : super(const AnimalRegistrationSelectionState());

  void selectSpecies(String speciesId) {
    if (AnimalCatalogue.speciesById(speciesId) == null) {
      throw ArgumentError.value(speciesId, 'speciesId');
    }
    state = AnimalRegistrationSelectionState(
      selectedSpeciesId: speciesId,
      customSpeciesName: state.selectedSpeciesId == speciesId
          ? state.customSpeciesName
          : '',
    );
  }

  void selectBreed(String breedId) {
    final breed = AnimalCatalogue.breedById(breedId);
    if (breed == null || breed.speciesId != state.selectedSpeciesId) {
      throw ArgumentError('Breed does not belong to the selected species.');
    }
    state = state.copyWith(
      selectedBreedId: breedId,
      customBreedName: state.selectedBreedId == breedId
          ? state.customBreedName
          : '',
      clearBreedError: true,
    );
  }

  void setCustomSpecies(String value) {
    state = state.copyWith(customSpeciesName: value, clearSpeciesError: true);
  }

  void setCustomBreed(String value) {
    state = state.copyWith(customBreedName: value, clearBreedError: true);
  }

  bool validate() {
    String? speciesError;
    String? breedError;
    if (state.selectedSpecies == null) {
      speciesError = 'Please select a species.';
    } else if (state.requiresCustomSpecies &&
        state.customSpeciesName.trim().isEmpty) {
      speciesError = 'Please enter the animal species.';
    }
    if (state.selectedBreed == null) {
      breedError = 'Please select a breed or choose Unknown/Not Specified.';
    } else if (state.selectedBreed!.speciesId != state.selectedSpeciesId) {
      breedError = 'The selected breed does not belong to this species.';
    } else if (state.requiresCustomBreed &&
        state.customBreedName.trim().isEmpty) {
      breedError = 'Please enter the breed or variety.';
    }
    state = state.copyWith(
      speciesValidationError: speciesError,
      breedValidationError: breedError,
      clearSpeciesError: speciesError == null,
      clearBreedError: breedError == null,
    );
    return speciesError == null && breedError == null;
  }
}

final animalRegistrationSelectionProvider =
    StateNotifierProvider.autoDispose<
      AnimalRegistrationSelectionController,
      AnimalRegistrationSelectionState
    >((ref) => AnimalRegistrationSelectionController());
