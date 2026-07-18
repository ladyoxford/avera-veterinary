import 'package:freezed_annotation/freezed_annotation.dart';

part 'animal_search_result.freezed.dart';
part 'animal_search_result.g.dart';

@freezed
abstract class AnimalSearchResult with _$AnimalSearchResult {
  const factory AnimalSearchResult({
    required int animalId,
    required String hospitalNumber,
    required String animalName,
    required String species,
    String? breed,
    String? sex,
    DateTime? dateRegistered,
    required String ownerName,
    required String ownerPhone,
    String? photo,
    required String status,
    DateTime? statusUpdatedAt,
  }) = _AnimalSearchResult;

  factory AnimalSearchResult.fromJson(Map<String, dynamic> json) =>
      _$AnimalSearchResultFromJson(json);
}
