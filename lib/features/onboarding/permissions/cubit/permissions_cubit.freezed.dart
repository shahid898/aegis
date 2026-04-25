// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'permissions_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PermissionsState {

 Map<AegisPermission, PermissionStatus> get statuses; bool get isRequesting;
/// Create a copy of PermissionsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PermissionsStateCopyWith<PermissionsState> get copyWith => _$PermissionsStateCopyWithImpl<PermissionsState>(this as PermissionsState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PermissionsState&&const DeepCollectionEquality().equals(other.statuses, statuses)&&(identical(other.isRequesting, isRequesting) || other.isRequesting == isRequesting));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(statuses),isRequesting);

@override
String toString() {
  return 'PermissionsState(statuses: $statuses, isRequesting: $isRequesting)';
}


}

/// @nodoc
abstract mixin class $PermissionsStateCopyWith<$Res>  {
  factory $PermissionsStateCopyWith(PermissionsState value, $Res Function(PermissionsState) _then) = _$PermissionsStateCopyWithImpl;
@useResult
$Res call({
 Map<AegisPermission, PermissionStatus> statuses, bool isRequesting
});




}
/// @nodoc
class _$PermissionsStateCopyWithImpl<$Res>
    implements $PermissionsStateCopyWith<$Res> {
  _$PermissionsStateCopyWithImpl(this._self, this._then);

  final PermissionsState _self;
  final $Res Function(PermissionsState) _then;

/// Create a copy of PermissionsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? statuses = null,Object? isRequesting = null,}) {
  return _then(_self.copyWith(
statuses: null == statuses ? _self.statuses : statuses // ignore: cast_nullable_to_non_nullable
as Map<AegisPermission, PermissionStatus>,isRequesting: null == isRequesting ? _self.isRequesting : isRequesting // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [PermissionsState].
extension PermissionsStatePatterns on PermissionsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PermissionsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PermissionsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PermissionsState value)  $default,){
final _that = this;
switch (_that) {
case _PermissionsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PermissionsState value)?  $default,){
final _that = this;
switch (_that) {
case _PermissionsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<AegisPermission, PermissionStatus> statuses,  bool isRequesting)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PermissionsState() when $default != null:
return $default(_that.statuses,_that.isRequesting);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<AegisPermission, PermissionStatus> statuses,  bool isRequesting)  $default,) {final _that = this;
switch (_that) {
case _PermissionsState():
return $default(_that.statuses,_that.isRequesting);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<AegisPermission, PermissionStatus> statuses,  bool isRequesting)?  $default,) {final _that = this;
switch (_that) {
case _PermissionsState() when $default != null:
return $default(_that.statuses,_that.isRequesting);case _:
  return null;

}
}

}

/// @nodoc


class _PermissionsState implements PermissionsState {
  const _PermissionsState({final  Map<AegisPermission, PermissionStatus> statuses = const <AegisPermission, PermissionStatus>{}, this.isRequesting = false}): _statuses = statuses;
  

 final  Map<AegisPermission, PermissionStatus> _statuses;
@override@JsonKey() Map<AegisPermission, PermissionStatus> get statuses {
  if (_statuses is EqualUnmodifiableMapView) return _statuses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_statuses);
}

@override@JsonKey() final  bool isRequesting;

/// Create a copy of PermissionsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PermissionsStateCopyWith<_PermissionsState> get copyWith => __$PermissionsStateCopyWithImpl<_PermissionsState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PermissionsState&&const DeepCollectionEquality().equals(other._statuses, _statuses)&&(identical(other.isRequesting, isRequesting) || other.isRequesting == isRequesting));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_statuses),isRequesting);

@override
String toString() {
  return 'PermissionsState(statuses: $statuses, isRequesting: $isRequesting)';
}


}

/// @nodoc
abstract mixin class _$PermissionsStateCopyWith<$Res> implements $PermissionsStateCopyWith<$Res> {
  factory _$PermissionsStateCopyWith(_PermissionsState value, $Res Function(_PermissionsState) _then) = __$PermissionsStateCopyWithImpl;
@override @useResult
$Res call({
 Map<AegisPermission, PermissionStatus> statuses, bool isRequesting
});




}
/// @nodoc
class __$PermissionsStateCopyWithImpl<$Res>
    implements _$PermissionsStateCopyWith<$Res> {
  __$PermissionsStateCopyWithImpl(this._self, this._then);

  final _PermissionsState _self;
  final $Res Function(_PermissionsState) _then;

/// Create a copy of PermissionsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? statuses = null,Object? isRequesting = null,}) {
  return _then(_PermissionsState(
statuses: null == statuses ? _self._statuses : statuses // ignore: cast_nullable_to_non_nullable
as Map<AegisPermission, PermissionStatus>,isRequesting: null == isRequesting ? _self.isRequesting : isRequesting // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
