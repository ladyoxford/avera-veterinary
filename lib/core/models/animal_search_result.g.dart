// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'animal_search_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AnimalSearchResult _$AnimalSearchResultFromJson(Map<String, dynamic> json) =>
    _AnimalSearchResult(
      animalId: (json['animalId'] as num).toInt(),
      hospitalNumber: json['hospitalNumber'] as String,
      animalName: json['animalName'] as String,
      species: json['species'] as String,
      breed: json['breed'] as String?,
      sex: json['sex'] as String?,
      dateRegistered: json['dateRegistered'] == null
          ? null
          : DateTime.parse(json['dateRegistered'] as String),
      ownerName: json['ownerName'] as String,
      ownerPhone: json['ownerPhone'] as String,
      photo: json['photo'] as String?,
      status: json['status'] as String,
      statusUpdatedAt: json['statusUpdatedAt'] == null
          ? null
          : DateTime.parse(json['statusUpdatedAt'] as String),
    );

Map<String, dynamic> _$AnimalSearchResultToJson(_AnimalSearchResult instance) =>
    <String, dynamic>{
      'animalId': instance.animalId,
      'hospitalNumber': instance.hospitalNumber,
      'animalName': instance.animalName,
      'species': instance.species,
      'breed': instance.breed,
      'sex': instance.sex,
      'dateRegistered': instance.dateRegistered?.toIso8601String(),
      'ownerName': instance.ownerName,
      'ownerPhone': instance.ownerPhone,
      'photo': instance.photo,
      'status': instance.status,
      'statusUpdatedAt': instance.statusUpdatedAt?.toIso8601String(),
    };
