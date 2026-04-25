// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'region_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RegionState {

 LatLng get center; double get zoom; LatLng? get pickedPoint; AppRegion? get region; bool get isResolvingGps; String? get errorMessage;
/// Create a copy of RegionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RegionStateCopyWith<RegionState> get copyWith => _$RegionStateCopyWithImpl<RegionState>(this as RegionState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RegionState&&(identical(other.center, center) || other.center == center)&&(identical(other.zoom, zoom) || other.zoom == zoom)&&(identical(other.pickedPoint, pickedPoint) || other.pickedPoint == pickedPoint)&&(identical(other.region, region) || other.region == region)&&(identical(other.isResolvingGps, isResolvingGps) || other.isResolvingGps == isResolvingGps)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,center,zoom,pickedPoint,region,isResolvingGps,errorMessage);

@override
String toString() {
  return 'RegionState(center: $center, zoom: $zoom, pickedPoint: $pickedPoint, region: $region, isResolvingGps: $isResolvingGps, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $RegionStateCopyWith<$Res>  {
  factory $RegionStateCopyWith(RegionState value, $Res Function(RegionState) _then) = _$RegionStateCopyWithImpl;
@useResult
$Res call({
 LatLng center, double zoom, LatLng? pickedPoint, AppRegion? region, bool isResolvingGps, String? errorMessage
});


$AppRegionCopyWith<$Res>? get region;

}
/// @nodoc
class _$RegionStateCopyWithImpl<$Res>
    implements $RegionStateCopyWith<$Res> {
  _$RegionStateCopyWithImpl(this._self, this._then);

  final RegionState _self;
  final $Res Function(RegionState) _then;

/// Create a copy of RegionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? center = null,Object? zoom = null,Object? pickedPoint = freezed,Object? region = freezed,Object? isResolvingGps = null,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
center: null == center ? _self.center : center // ignore: cast_nullable_to_non_nullable
as LatLng,zoom: null == zoom ? _self.zoom : zoom // ignore: cast_nullable_to_non_nullable
as double,pickedPoint: freezed == pickedPoint ? _self.pickedPoint : pickedPoint // ignore: cast_nullable_to_non_nullable
as LatLng?,region: freezed == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as AppRegion?,isResolvingGps: null == isResolvingGps ? _self.isResolvingGps : isResolvingGps // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of RegionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppRegionCopyWith<$Res>? get region {
    if (_self.region == null) {
    return null;
  }

  return $AppRegionCopyWith<$Res>(_self.region!, (value) {
    return _then(_self.copyWith(region: value));
  });
}
}


/// Adds pattern-matching-related methods to [RegionState].
extension RegionStatePatterns on RegionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RegionState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RegionState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RegionState value)  $default,){
final _that = this;
switch (_that) {
case _RegionState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RegionState value)?  $default,){
final _that = this;
switch (_that) {
case _RegionState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LatLng center,  double zoom,  LatLng? pickedPoint,  AppRegion? region,  bool isResolvingGps,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RegionState() when $default != null:
return $default(_that.center,_that.zoom,_that.pickedPoint,_that.region,_that.isResolvingGps,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LatLng center,  double zoom,  LatLng? pickedPoint,  AppRegion? region,  bool isResolvingGps,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _RegionState():
return $default(_that.center,_that.zoom,_that.pickedPoint,_that.region,_that.isResolvingGps,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LatLng center,  double zoom,  LatLng? pickedPoint,  AppRegion? region,  bool isResolvingGps,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _RegionState() when $default != null:
return $default(_that.center,_that.zoom,_that.pickedPoint,_that.region,_that.isResolvingGps,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _RegionState implements RegionState {
  const _RegionState({this.center = const LatLng(20.5937, 78.9629), this.zoom = 3.5, this.pickedPoint, this.region, this.isResolvingGps = false, this.errorMessage});
  

@override@JsonKey() final  LatLng center;
@override@JsonKey() final  double zoom;
@override final  LatLng? pickedPoint;
@override final  AppRegion? region;
@override@JsonKey() final  bool isResolvingGps;
@override final  String? errorMessage;

/// Create a copy of RegionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RegionStateCopyWith<_RegionState> get copyWith => __$RegionStateCopyWithImpl<_RegionState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RegionState&&(identical(other.center, center) || other.center == center)&&(identical(other.zoom, zoom) || other.zoom == zoom)&&(identical(other.pickedPoint, pickedPoint) || other.pickedPoint == pickedPoint)&&(identical(other.region, region) || other.region == region)&&(identical(other.isResolvingGps, isResolvingGps) || other.isResolvingGps == isResolvingGps)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,center,zoom,pickedPoint,region,isResolvingGps,errorMessage);

@override
String toString() {
  return 'RegionState(center: $center, zoom: $zoom, pickedPoint: $pickedPoint, region: $region, isResolvingGps: $isResolvingGps, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$RegionStateCopyWith<$Res> implements $RegionStateCopyWith<$Res> {
  factory _$RegionStateCopyWith(_RegionState value, $Res Function(_RegionState) _then) = __$RegionStateCopyWithImpl;
@override @useResult
$Res call({
 LatLng center, double zoom, LatLng? pickedPoint, AppRegion? region, bool isResolvingGps, String? errorMessage
});


@override $AppRegionCopyWith<$Res>? get region;

}
/// @nodoc
class __$RegionStateCopyWithImpl<$Res>
    implements _$RegionStateCopyWith<$Res> {
  __$RegionStateCopyWithImpl(this._self, this._then);

  final _RegionState _self;
  final $Res Function(_RegionState) _then;

/// Create a copy of RegionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? center = null,Object? zoom = null,Object? pickedPoint = freezed,Object? region = freezed,Object? isResolvingGps = null,Object? errorMessage = freezed,}) {
  return _then(_RegionState(
center: null == center ? _self.center : center // ignore: cast_nullable_to_non_nullable
as LatLng,zoom: null == zoom ? _self.zoom : zoom // ignore: cast_nullable_to_non_nullable
as double,pickedPoint: freezed == pickedPoint ? _self.pickedPoint : pickedPoint // ignore: cast_nullable_to_non_nullable
as LatLng?,region: freezed == region ? _self.region : region // ignore: cast_nullable_to_non_nullable
as AppRegion?,isResolvingGps: null == isResolvingGps ? _self.isResolvingGps : isResolvingGps // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of RegionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AppRegionCopyWith<$Res>? get region {
    if (_self.region == null) {
    return null;
  }

  return $AppRegionCopyWith<$Res>(_self.region!, (value) {
    return _then(_self.copyWith(region: value));
  });
}
}

// dart format on
