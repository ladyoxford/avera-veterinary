// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'animal_search_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AnimalSearchResult {

 int get animalId; String get hospitalNumber; String get animalName; String get species; String? get breed; String? get sex; DateTime? get dateRegistered; String get ownerName; String get ownerPhone; String? get photo; String get status; DateTime? get statusUpdatedAt;
/// Create a copy of AnimalSearchResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnimalSearchResultCopyWith<AnimalSearchResult> get copyWith => _$AnimalSearchResultCopyWithImpl<AnimalSearchResult>(this as AnimalSearchResult, _$identity);

  /// Serializes this AnimalSearchResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnimalSearchResult&&(identical(other.animalId, animalId) || other.animalId == animalId)&&(identical(other.hospitalNumber, hospitalNumber) || other.hospitalNumber == hospitalNumber)&&(identical(other.animalName, animalName) || other.animalName == animalName)&&(identical(other.species, species) || other.species == species)&&(identical(other.breed, breed) || other.breed == breed)&&(identical(other.sex, sex) || other.sex == sex)&&(identical(other.dateRegistered, dateRegistered) || other.dateRegistered == dateRegistered)&&(identical(other.ownerName, ownerName) || other.ownerName == ownerName)&&(identical(other.ownerPhone, ownerPhone) || other.ownerPhone == ownerPhone)&&(identical(other.photo, photo) || other.photo == photo)&&(identical(other.status, status) || other.status == status)&&(identical(other.statusUpdatedAt, statusUpdatedAt) || other.statusUpdatedAt == statusUpdatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,animalId,hospitalNumber,animalName,species,breed,sex,dateRegistered,ownerName,ownerPhone,photo,status,statusUpdatedAt);

@override
String toString() {
  return 'AnimalSearchResult(animalId: $animalId, hospitalNumber: $hospitalNumber, animalName: $animalName, species: $species, breed: $breed, sex: $sex, dateRegistered: $dateRegistered, ownerName: $ownerName, ownerPhone: $ownerPhone, photo: $photo, status: $status, statusUpdatedAt: $statusUpdatedAt)';
}


}

/// @nodoc
abstract mixin class $AnimalSearchResultCopyWith<$Res>  {
  factory $AnimalSearchResultCopyWith(AnimalSearchResult value, $Res Function(AnimalSearchResult) _then) = _$AnimalSearchResultCopyWithImpl;
@useResult
$Res call({
 int animalId, String hospitalNumber, String animalName, String species, String? breed, String? sex, DateTime? dateRegistered, String ownerName, String ownerPhone, String? photo, String status, DateTime? statusUpdatedAt
});




}
/// @nodoc
class _$AnimalSearchResultCopyWithImpl<$Res>
    implements $AnimalSearchResultCopyWith<$Res> {
  _$AnimalSearchResultCopyWithImpl(this._self, this._then);

  final AnimalSearchResult _self;
  final $Res Function(AnimalSearchResult) _then;

/// Create a copy of AnimalSearchResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? animalId = null,Object? hospitalNumber = null,Object? animalName = null,Object? species = null,Object? breed = freezed,Object? sex = freezed,Object? dateRegistered = freezed,Object? ownerName = null,Object? ownerPhone = null,Object? photo = freezed,Object? status = null,Object? statusUpdatedAt = freezed,}) {
  return _then(_self.copyWith(
animalId: null == animalId ? _self.animalId : animalId // ignore: cast_nullable_to_non_nullable
as int,hospitalNumber: null == hospitalNumber ? _self.hospitalNumber : hospitalNumber // ignore: cast_nullable_to_non_nullable
as String,animalName: null == animalName ? _self.animalName : animalName // ignore: cast_nullable_to_non_nullable
as String,species: null == species ? _self.species : species // ignore: cast_nullable_to_non_nullable
as String,breed: freezed == breed ? _self.breed : breed // ignore: cast_nullable_to_non_nullable
as String?,sex: freezed == sex ? _self.sex : sex // ignore: cast_nullable_to_non_nullable
as String?,dateRegistered: freezed == dateRegistered ? _self.dateRegistered : dateRegistered // ignore: cast_nullable_to_non_nullable
as DateTime?,ownerName: null == ownerName ? _self.ownerName : ownerName // ignore: cast_nullable_to_non_nullable
as String,ownerPhone: null == ownerPhone ? _self.ownerPhone : ownerPhone // ignore: cast_nullable_to_non_nullable
as String,photo: freezed == photo ? _self.photo : photo // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,statusUpdatedAt: freezed == statusUpdatedAt ? _self.statusUpdatedAt : statusUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [AnimalSearchResult].
extension AnimalSearchResultPatterns on AnimalSearchResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AnimalSearchResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AnimalSearchResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AnimalSearchResult value)  $default,){
final _that = this;
switch (_that) {
case _AnimalSearchResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AnimalSearchResult value)?  $default,){
final _that = this;
switch (_that) {
case _AnimalSearchResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int animalId,  String hospitalNumber,  String animalName,  String species,  String? breed,  String? sex,  DateTime? dateRegistered,  String ownerName,  String ownerPhone,  String? photo,  String status,  DateTime? statusUpdatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AnimalSearchResult() when $default != null:
return $default(_that.animalId,_that.hospitalNumber,_that.animalName,_that.species,_that.breed,_that.sex,_that.dateRegistered,_that.ownerName,_that.ownerPhone,_that.photo,_that.status,_that.statusUpdatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int animalId,  String hospitalNumber,  String animalName,  String species,  String? breed,  String? sex,  DateTime? dateRegistered,  String ownerName,  String ownerPhone,  String? photo,  String status,  DateTime? statusUpdatedAt)  $default,) {final _that = this;
switch (_that) {
case _AnimalSearchResult():
return $default(_that.animalId,_that.hospitalNumber,_that.animalName,_that.species,_that.breed,_that.sex,_that.dateRegistered,_that.ownerName,_that.ownerPhone,_that.photo,_that.status,_that.statusUpdatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int animalId,  String hospitalNumber,  String animalName,  String species,  String? breed,  String? sex,  DateTime? dateRegistered,  String ownerName,  String ownerPhone,  String? photo,  String status,  DateTime? statusUpdatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AnimalSearchResult() when $default != null:
return $default(_that.animalId,_that.hospitalNumber,_that.animalName,_that.species,_that.breed,_that.sex,_that.dateRegistered,_that.ownerName,_that.ownerPhone,_that.photo,_that.status,_that.statusUpdatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AnimalSearchResult implements AnimalSearchResult {
  const _AnimalSearchResult({required this.animalId, required this.hospitalNumber, required this.animalName, required this.species, this.breed, this.sex, this.dateRegistered, required this.ownerName, required this.ownerPhone, this.photo, required this.status, this.statusUpdatedAt});
  factory _AnimalSearchResult.fromJson(Map<String, dynamic> json) => _$AnimalSearchResultFromJson(json);

@override final  int animalId;
@override final  String hospitalNumber;
@override final  String animalName;
@override final  String species;
@override final  String? breed;
@override final  String? sex;
@override final  DateTime? dateRegistered;
@override final  String ownerName;
@override final  String ownerPhone;
@override final  String? photo;
@override final  String status;
@override final  DateTime? statusUpdatedAt;

/// Create a copy of AnimalSearchResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnimalSearchResultCopyWith<_AnimalSearchResult> get copyWith => __$AnimalSearchResultCopyWithImpl<_AnimalSearchResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AnimalSearchResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AnimalSearchResult&&(identical(other.animalId, animalId) || other.animalId == animalId)&&(identical(other.hospitalNumber, hospitalNumber) || other.hospitalNumber == hospitalNumber)&&(identical(other.animalName, animalName) || other.animalName == animalName)&&(identical(other.species, species) || other.species == species)&&(identical(other.breed, breed) || other.breed == breed)&&(identical(other.sex, sex) || other.sex == sex)&&(identical(other.dateRegistered, dateRegistered) || other.dateRegistered == dateRegistered)&&(identical(other.ownerName, ownerName) || other.ownerName == ownerName)&&(identical(other.ownerPhone, ownerPhone) || other.ownerPhone == ownerPhone)&&(identical(other.photo, photo) || other.photo == photo)&&(identical(other.status, status) || other.status == status)&&(identical(other.statusUpdatedAt, statusUpdatedAt) || other.statusUpdatedAt == statusUpdatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,animalId,hospitalNumber,animalName,species,breed,sex,dateRegistered,ownerName,ownerPhone,photo,status,statusUpdatedAt);

@override
String toString() {
  return 'AnimalSearchResult(animalId: $animalId, hospitalNumber: $hospitalNumber, animalName: $animalName, species: $species, breed: $breed, sex: $sex, dateRegistered: $dateRegistered, ownerName: $ownerName, ownerPhone: $ownerPhone, photo: $photo, status: $status, statusUpdatedAt: $statusUpdatedAt)';
}


}

/// @nodoc
abstract mixin class _$AnimalSearchResultCopyWith<$Res> implements $AnimalSearchResultCopyWith<$Res> {
  factory _$AnimalSearchResultCopyWith(_AnimalSearchResult value, $Res Function(_AnimalSearchResult) _then) = __$AnimalSearchResultCopyWithImpl;
@override @useResult
$Res call({
 int animalId, String hospitalNumber, String animalName, String species, String? breed, String? sex, DateTime? dateRegistered, String ownerName, String ownerPhone, String? photo, String status, DateTime? statusUpdatedAt
});




}
/// @nodoc
class __$AnimalSearchResultCopyWithImpl<$Res>
    implements _$AnimalSearchResultCopyWith<$Res> {
  __$AnimalSearchResultCopyWithImpl(this._self, this._then);

  final _AnimalSearchResult _self;
  final $Res Function(_AnimalSearchResult) _then;

/// Create a copy of AnimalSearchResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? animalId = null,Object? hospitalNumber = null,Object? animalName = null,Object? species = null,Object? breed = freezed,Object? sex = freezed,Object? dateRegistered = freezed,Object? ownerName = null,Object? ownerPhone = null,Object? photo = freezed,Object? status = null,Object? statusUpdatedAt = freezed,}) {
  return _then(_AnimalSearchResult(
animalId: null == animalId ? _self.animalId : animalId // ignore: cast_nullable_to_non_nullable
as int,hospitalNumber: null == hospitalNumber ? _self.hospitalNumber : hospitalNumber // ignore: cast_nullable_to_non_nullable
as String,animalName: null == animalName ? _self.animalName : animalName // ignore: cast_nullable_to_non_nullable
as String,species: null == species ? _self.species : species // ignore: cast_nullable_to_non_nullable
as String,breed: freezed == breed ? _self.breed : breed // ignore: cast_nullable_to_non_nullable
as String?,sex: freezed == sex ? _self.sex : sex // ignore: cast_nullable_to_non_nullable
as String?,dateRegistered: freezed == dateRegistered ? _self.dateRegistered : dateRegistered // ignore: cast_nullable_to_non_nullable
as DateTime?,ownerName: null == ownerName ? _self.ownerName : ownerName // ignore: cast_nullable_to_non_nullable
as String,ownerPhone: null == ownerPhone ? _self.ownerPhone : ownerPhone // ignore: cast_nullable_to_non_nullable
as String,photo: freezed == photo ? _self.photo : photo // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,statusUpdatedAt: freezed == statusUpdatedAt ? _self.statusUpdatedAt : statusUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
