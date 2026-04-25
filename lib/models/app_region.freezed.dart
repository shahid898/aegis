// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_region.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AppRegion {

 String get districtName; String get countryCode; double get latitude; double get longitude;
/// Create a copy of AppRegion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppRegionCopyWith<AppRegion> get copyWith => _$AppRegionCopyWithImpl<AppRegion>(this as AppRegion, _$identity);

  /// Serializes this AppRegion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppRegion&&(identical(other.districtName, districtName) || other.districtName == districtName)&&(identical(other.countryCode, countryCode) || other.countryCode == countryCode)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,districtName,countryCode,latitude,longitude);

@override
String toString() {
  return 'AppRegion(districtName: $districtName, countryCode: $countryCode, latitude: $latitude, longitude: $longitude)';
}


}

/// @nodoc
abstract mixin class $AppRegionCopyWith<$Res>  {
  factory $AppRegionCopyWith(AppRegion value, $Res Function(AppRegion) _then) = _$AppRegionCopyWithImpl;
@useResult
$Res call({
 String districtName, String countryCode, double latitude, double longitude
});




}
/// @nodoc
class _$AppRegionCopyWithImpl<$Res>
    implements $AppRegionCopyWith<$Res> {
  _$AppRegionCopyWithImpl(this._self, this._then);

  final AppRegion _self;
  final $Res Function(AppRegion) _then;

/// Create a copy of AppRegion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? districtName = null,Object? countryCode = null,Object? latitude = null,Object? longitude = null,}) {
  return _then(_self.copyWith(
districtName: null == districtName ? _self.districtName : districtName // ignore: cast_nullable_to_non_nullable
as String,countryCode: null == countryCode ? _self.countryCode : countryCode // ignore: cast_nullable_to_non_nullable
as String,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [AppRegion].
extension AppRegionPatterns on AppRegion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppRegion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppRegion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppRegion value)  $default,){
final _that = this;
switch (_that) {
case _AppRegion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppRegion value)?  $default,){
final _that = this;
switch (_that) {
case _AppRegion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String districtName,  String countryCode,  double latitude,  double longitude)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppRegion() when $default != null:
return $default(_that.districtName,_that.countryCode,_that.latitude,_that.longitude);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String districtName,  String countryCode,  double latitude,  double longitude)  $default,) {final _that = this;
switch (_that) {
case _AppRegion():
return $default(_that.districtName,_that.countryCode,_that.latitude,_that.longitude);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String districtName,  String countryCode,  double latitude,  double longitude)?  $default,) {final _that = this;
switch (_that) {
case _AppRegion() when $default != null:
return $default(_that.districtName,_that.countryCode,_that.latitude,_that.longitude);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AppRegion implements AppRegion {
  const _AppRegion({required this.districtName, required this.countryCode, required this.latitude, required this.longitude});
  factory _AppRegion.fromJson(Map<String, dynamic> json) => _$AppRegionFromJson(json);

@override final  String districtName;
@override final  String countryCode;
@override final  double latitude;
@override final  double longitude;

/// Create a copy of AppRegion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppRegionCopyWith<_AppRegion> get copyWith => __$AppRegionCopyWithImpl<_AppRegion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AppRegionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppRegion&&(identical(other.districtName, districtName) || other.districtName == districtName)&&(identical(other.countryCode, countryCode) || other.countryCode == countryCode)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,districtName,countryCode,latitude,longitude);

@override
String toString() {
  return 'AppRegion(districtName: $districtName, countryCode: $countryCode, latitude: $latitude, longitude: $longitude)';
}


}

/// @nodoc
abstract mixin class _$AppRegionCopyWith<$Res> implements $AppRegionCopyWith<$Res> {
  factory _$AppRegionCopyWith(_AppRegion value, $Res Function(_AppRegion) _then) = __$AppRegionCopyWithImpl;
@override @useResult
$Res call({
 String districtName, String countryCode, double latitude, double longitude
});




}
/// @nodoc
class __$AppRegionCopyWithImpl<$Res>
    implements _$AppRegionCopyWith<$Res> {
  __$AppRegionCopyWithImpl(this._self, this._then);

  final _AppRegion _self;
  final $Res Function(_AppRegion) _then;

/// Create a copy of AppRegion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? districtName = null,Object? countryCode = null,Object? latitude = null,Object? longitude = null,}) {
  return _then(_AppRegion(
districtName: null == districtName ? _self.districtName : districtName // ignore: cast_nullable_to_non_nullable
as String,countryCode: null == countryCode ? _self.countryCode : countryCode // ignore: cast_nullable_to_non_nullable
as String,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
