// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'accessibility_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AccessibilityProfile {

 bool get usesWheelchair; bool get takesDailyMedication; bool get hasDependent;
/// Create a copy of AccessibilityProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccessibilityProfileCopyWith<AccessibilityProfile> get copyWith => _$AccessibilityProfileCopyWithImpl<AccessibilityProfile>(this as AccessibilityProfile, _$identity);

  /// Serializes this AccessibilityProfile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccessibilityProfile&&(identical(other.usesWheelchair, usesWheelchair) || other.usesWheelchair == usesWheelchair)&&(identical(other.takesDailyMedication, takesDailyMedication) || other.takesDailyMedication == takesDailyMedication)&&(identical(other.hasDependent, hasDependent) || other.hasDependent == hasDependent));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,usesWheelchair,takesDailyMedication,hasDependent);

@override
String toString() {
  return 'AccessibilityProfile(usesWheelchair: $usesWheelchair, takesDailyMedication: $takesDailyMedication, hasDependent: $hasDependent)';
}


}

/// @nodoc
abstract mixin class $AccessibilityProfileCopyWith<$Res>  {
  factory $AccessibilityProfileCopyWith(AccessibilityProfile value, $Res Function(AccessibilityProfile) _then) = _$AccessibilityProfileCopyWithImpl;
@useResult
$Res call({
 bool usesWheelchair, bool takesDailyMedication, bool hasDependent
});




}
/// @nodoc
class _$AccessibilityProfileCopyWithImpl<$Res>
    implements $AccessibilityProfileCopyWith<$Res> {
  _$AccessibilityProfileCopyWithImpl(this._self, this._then);

  final AccessibilityProfile _self;
  final $Res Function(AccessibilityProfile) _then;

/// Create a copy of AccessibilityProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? usesWheelchair = null,Object? takesDailyMedication = null,Object? hasDependent = null,}) {
  return _then(_self.copyWith(
usesWheelchair: null == usesWheelchair ? _self.usesWheelchair : usesWheelchair // ignore: cast_nullable_to_non_nullable
as bool,takesDailyMedication: null == takesDailyMedication ? _self.takesDailyMedication : takesDailyMedication // ignore: cast_nullable_to_non_nullable
as bool,hasDependent: null == hasDependent ? _self.hasDependent : hasDependent // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AccessibilityProfile].
extension AccessibilityProfilePatterns on AccessibilityProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccessibilityProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccessibilityProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccessibilityProfile value)  $default,){
final _that = this;
switch (_that) {
case _AccessibilityProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccessibilityProfile value)?  $default,){
final _that = this;
switch (_that) {
case _AccessibilityProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool usesWheelchair,  bool takesDailyMedication,  bool hasDependent)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccessibilityProfile() when $default != null:
return $default(_that.usesWheelchair,_that.takesDailyMedication,_that.hasDependent);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool usesWheelchair,  bool takesDailyMedication,  bool hasDependent)  $default,) {final _that = this;
switch (_that) {
case _AccessibilityProfile():
return $default(_that.usesWheelchair,_that.takesDailyMedication,_that.hasDependent);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool usesWheelchair,  bool takesDailyMedication,  bool hasDependent)?  $default,) {final _that = this;
switch (_that) {
case _AccessibilityProfile() when $default != null:
return $default(_that.usesWheelchair,_that.takesDailyMedication,_that.hasDependent);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AccessibilityProfile implements AccessibilityProfile {
  const _AccessibilityProfile({this.usesWheelchair = false, this.takesDailyMedication = false, this.hasDependent = false});
  factory _AccessibilityProfile.fromJson(Map<String, dynamic> json) => _$AccessibilityProfileFromJson(json);

@override@JsonKey() final  bool usesWheelchair;
@override@JsonKey() final  bool takesDailyMedication;
@override@JsonKey() final  bool hasDependent;

/// Create a copy of AccessibilityProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccessibilityProfileCopyWith<_AccessibilityProfile> get copyWith => __$AccessibilityProfileCopyWithImpl<_AccessibilityProfile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AccessibilityProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccessibilityProfile&&(identical(other.usesWheelchair, usesWheelchair) || other.usesWheelchair == usesWheelchair)&&(identical(other.takesDailyMedication, takesDailyMedication) || other.takesDailyMedication == takesDailyMedication)&&(identical(other.hasDependent, hasDependent) || other.hasDependent == hasDependent));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,usesWheelchair,takesDailyMedication,hasDependent);

@override
String toString() {
  return 'AccessibilityProfile(usesWheelchair: $usesWheelchair, takesDailyMedication: $takesDailyMedication, hasDependent: $hasDependent)';
}


}

/// @nodoc
abstract mixin class _$AccessibilityProfileCopyWith<$Res> implements $AccessibilityProfileCopyWith<$Res> {
  factory _$AccessibilityProfileCopyWith(_AccessibilityProfile value, $Res Function(_AccessibilityProfile) _then) = __$AccessibilityProfileCopyWithImpl;
@override @useResult
$Res call({
 bool usesWheelchair, bool takesDailyMedication, bool hasDependent
});




}
/// @nodoc
class __$AccessibilityProfileCopyWithImpl<$Res>
    implements _$AccessibilityProfileCopyWith<$Res> {
  __$AccessibilityProfileCopyWithImpl(this._self, this._then);

  final _AccessibilityProfile _self;
  final $Res Function(_AccessibilityProfile) _then;

/// Create a copy of AccessibilityProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? usesWheelchair = null,Object? takesDailyMedication = null,Object? hasDependent = null,}) {
  return _then(_AccessibilityProfile(
usesWheelchair: null == usesWheelchair ? _self.usesWheelchair : usesWheelchair // ignore: cast_nullable_to_non_nullable
as bool,takesDailyMedication: null == takesDailyMedication ? _self.takesDailyMedication : takesDailyMedication // ignore: cast_nullable_to_non_nullable
as bool,hasDependent: null == hasDependent ? _self.hasDependent : hasDependent // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
