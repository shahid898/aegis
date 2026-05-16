// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_download_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelDownloadState implements DiagnosticableTreeMixin {

 List<VoiceModelPack> get plan; Set<String> get installedIds; DownloadStatus get status; VoiceModelPack? get currentPack; int get currentReceivedBytes; int get currentTotalBytes; String? get errorMessage; String get placesProgressMessage; int get placesCount; String get tilesProgressMessage; double get tilesProgressFraction; int get tilesCached;/// Monotonic plan-wide progress in [0, 1]. Stored (not computed)
/// so we can clamp it against the previous value and prevent the
/// progress bar from rolling backwards — which used to happen
/// because `pack.approxBytes` is a hardcoded estimate and the
/// server-reported Content-Length sometimes flips the denominator
/// mid-flight. The cubit updates this via `_advanceProgress(...)`.
 double get overallFraction;
/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelDownloadStateCopyWith<ModelDownloadState> get copyWith => _$ModelDownloadStateCopyWithImpl<ModelDownloadState>(this as ModelDownloadState, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ModelDownloadState'))
    ..add(DiagnosticsProperty('plan', plan))..add(DiagnosticsProperty('installedIds', installedIds))..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('currentPack', currentPack))..add(DiagnosticsProperty('currentReceivedBytes', currentReceivedBytes))..add(DiagnosticsProperty('currentTotalBytes', currentTotalBytes))..add(DiagnosticsProperty('errorMessage', errorMessage))..add(DiagnosticsProperty('placesProgressMessage', placesProgressMessage))..add(DiagnosticsProperty('placesCount', placesCount))..add(DiagnosticsProperty('tilesProgressMessage', tilesProgressMessage))..add(DiagnosticsProperty('tilesProgressFraction', tilesProgressFraction))..add(DiagnosticsProperty('tilesCached', tilesCached))..add(DiagnosticsProperty('overallFraction', overallFraction));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelDownloadState&&const DeepCollectionEquality().equals(other.plan, plan)&&const DeepCollectionEquality().equals(other.installedIds, installedIds)&&(identical(other.status, status) || other.status == status)&&(identical(other.currentPack, currentPack) || other.currentPack == currentPack)&&(identical(other.currentReceivedBytes, currentReceivedBytes) || other.currentReceivedBytes == currentReceivedBytes)&&(identical(other.currentTotalBytes, currentTotalBytes) || other.currentTotalBytes == currentTotalBytes)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.placesProgressMessage, placesProgressMessage) || other.placesProgressMessage == placesProgressMessage)&&(identical(other.placesCount, placesCount) || other.placesCount == placesCount)&&(identical(other.tilesProgressMessage, tilesProgressMessage) || other.tilesProgressMessage == tilesProgressMessage)&&(identical(other.tilesProgressFraction, tilesProgressFraction) || other.tilesProgressFraction == tilesProgressFraction)&&(identical(other.tilesCached, tilesCached) || other.tilesCached == tilesCached)&&(identical(other.overallFraction, overallFraction) || other.overallFraction == overallFraction));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(plan),const DeepCollectionEquality().hash(installedIds),status,currentPack,currentReceivedBytes,currentTotalBytes,errorMessage,placesProgressMessage,placesCount,tilesProgressMessage,tilesProgressFraction,tilesCached,overallFraction);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ModelDownloadState(plan: $plan, installedIds: $installedIds, status: $status, currentPack: $currentPack, currentReceivedBytes: $currentReceivedBytes, currentTotalBytes: $currentTotalBytes, errorMessage: $errorMessage, placesProgressMessage: $placesProgressMessage, placesCount: $placesCount, tilesProgressMessage: $tilesProgressMessage, tilesProgressFraction: $tilesProgressFraction, tilesCached: $tilesCached, overallFraction: $overallFraction)';
}


}

/// @nodoc
abstract mixin class $ModelDownloadStateCopyWith<$Res>  {
  factory $ModelDownloadStateCopyWith(ModelDownloadState value, $Res Function(ModelDownloadState) _then) = _$ModelDownloadStateCopyWithImpl;
@useResult
$Res call({
 List<VoiceModelPack> plan, Set<String> installedIds, DownloadStatus status, VoiceModelPack? currentPack, int currentReceivedBytes, int currentTotalBytes, String? errorMessage, String placesProgressMessage, int placesCount, String tilesProgressMessage, double tilesProgressFraction, int tilesCached, double overallFraction
});




}
/// @nodoc
class _$ModelDownloadStateCopyWithImpl<$Res>
    implements $ModelDownloadStateCopyWith<$Res> {
  _$ModelDownloadStateCopyWithImpl(this._self, this._then);

  final ModelDownloadState _self;
  final $Res Function(ModelDownloadState) _then;

/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? plan = null,Object? installedIds = null,Object? status = null,Object? currentPack = freezed,Object? currentReceivedBytes = null,Object? currentTotalBytes = null,Object? errorMessage = freezed,Object? placesProgressMessage = null,Object? placesCount = null,Object? tilesProgressMessage = null,Object? tilesProgressFraction = null,Object? tilesCached = null,Object? overallFraction = null,}) {
  return _then(_self.copyWith(
plan: null == plan ? _self.plan : plan // ignore: cast_nullable_to_non_nullable
as List<VoiceModelPack>,installedIds: null == installedIds ? _self.installedIds : installedIds // ignore: cast_nullable_to_non_nullable
as Set<String>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,currentPack: freezed == currentPack ? _self.currentPack : currentPack // ignore: cast_nullable_to_non_nullable
as VoiceModelPack?,currentReceivedBytes: null == currentReceivedBytes ? _self.currentReceivedBytes : currentReceivedBytes // ignore: cast_nullable_to_non_nullable
as int,currentTotalBytes: null == currentTotalBytes ? _self.currentTotalBytes : currentTotalBytes // ignore: cast_nullable_to_non_nullable
as int,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,placesProgressMessage: null == placesProgressMessage ? _self.placesProgressMessage : placesProgressMessage // ignore: cast_nullable_to_non_nullable
as String,placesCount: null == placesCount ? _self.placesCount : placesCount // ignore: cast_nullable_to_non_nullable
as int,tilesProgressMessage: null == tilesProgressMessage ? _self.tilesProgressMessage : tilesProgressMessage // ignore: cast_nullable_to_non_nullable
as String,tilesProgressFraction: null == tilesProgressFraction ? _self.tilesProgressFraction : tilesProgressFraction // ignore: cast_nullable_to_non_nullable
as double,tilesCached: null == tilesCached ? _self.tilesCached : tilesCached // ignore: cast_nullable_to_non_nullable
as int,overallFraction: null == overallFraction ? _self.overallFraction : overallFraction // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelDownloadState].
extension ModelDownloadStatePatterns on ModelDownloadState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelDownloadState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelDownloadState value)  $default,){
final _that = this;
switch (_that) {
case _ModelDownloadState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelDownloadState value)?  $default,){
final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<VoiceModelPack> plan,  Set<String> installedIds,  DownloadStatus status,  VoiceModelPack? currentPack,  int currentReceivedBytes,  int currentTotalBytes,  String? errorMessage,  String placesProgressMessage,  int placesCount,  String tilesProgressMessage,  double tilesProgressFraction,  int tilesCached,  double overallFraction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
return $default(_that.plan,_that.installedIds,_that.status,_that.currentPack,_that.currentReceivedBytes,_that.currentTotalBytes,_that.errorMessage,_that.placesProgressMessage,_that.placesCount,_that.tilesProgressMessage,_that.tilesProgressFraction,_that.tilesCached,_that.overallFraction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<VoiceModelPack> plan,  Set<String> installedIds,  DownloadStatus status,  VoiceModelPack? currentPack,  int currentReceivedBytes,  int currentTotalBytes,  String? errorMessage,  String placesProgressMessage,  int placesCount,  String tilesProgressMessage,  double tilesProgressFraction,  int tilesCached,  double overallFraction)  $default,) {final _that = this;
switch (_that) {
case _ModelDownloadState():
return $default(_that.plan,_that.installedIds,_that.status,_that.currentPack,_that.currentReceivedBytes,_that.currentTotalBytes,_that.errorMessage,_that.placesProgressMessage,_that.placesCount,_that.tilesProgressMessage,_that.tilesProgressFraction,_that.tilesCached,_that.overallFraction);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<VoiceModelPack> plan,  Set<String> installedIds,  DownloadStatus status,  VoiceModelPack? currentPack,  int currentReceivedBytes,  int currentTotalBytes,  String? errorMessage,  String placesProgressMessage,  int placesCount,  String tilesProgressMessage,  double tilesProgressFraction,  int tilesCached,  double overallFraction)?  $default,) {final _that = this;
switch (_that) {
case _ModelDownloadState() when $default != null:
return $default(_that.plan,_that.installedIds,_that.status,_that.currentPack,_that.currentReceivedBytes,_that.currentTotalBytes,_that.errorMessage,_that.placesProgressMessage,_that.placesCount,_that.tilesProgressMessage,_that.tilesProgressFraction,_that.tilesCached,_that.overallFraction);case _:
  return null;

}
}

}

/// @nodoc


class _ModelDownloadState extends ModelDownloadState with DiagnosticableTreeMixin {
  const _ModelDownloadState({required final  List<VoiceModelPack> plan, final  Set<String> installedIds = const <String>{}, this.status = DownloadStatus.idle, this.currentPack, this.currentReceivedBytes = 0, this.currentTotalBytes = 1, this.errorMessage, this.placesProgressMessage = '', this.placesCount = 0, this.tilesProgressMessage = '', this.tilesProgressFraction = 0.0, this.tilesCached = 0, this.overallFraction = 0.0}): _plan = plan,_installedIds = installedIds,super._();
  

 final  List<VoiceModelPack> _plan;
@override List<VoiceModelPack> get plan {
  if (_plan is EqualUnmodifiableListView) return _plan;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_plan);
}

 final  Set<String> _installedIds;
@override@JsonKey() Set<String> get installedIds {
  if (_installedIds is EqualUnmodifiableSetView) return _installedIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_installedIds);
}

@override@JsonKey() final  DownloadStatus status;
@override final  VoiceModelPack? currentPack;
@override@JsonKey() final  int currentReceivedBytes;
@override@JsonKey() final  int currentTotalBytes;
@override final  String? errorMessage;
@override@JsonKey() final  String placesProgressMessage;
@override@JsonKey() final  int placesCount;
@override@JsonKey() final  String tilesProgressMessage;
@override@JsonKey() final  double tilesProgressFraction;
@override@JsonKey() final  int tilesCached;
/// Monotonic plan-wide progress in [0, 1]. Stored (not computed)
/// so we can clamp it against the previous value and prevent the
/// progress bar from rolling backwards — which used to happen
/// because `pack.approxBytes` is a hardcoded estimate and the
/// server-reported Content-Length sometimes flips the denominator
/// mid-flight. The cubit updates this via `_advanceProgress(...)`.
@override@JsonKey() final  double overallFraction;

/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelDownloadStateCopyWith<_ModelDownloadState> get copyWith => __$ModelDownloadStateCopyWithImpl<_ModelDownloadState>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'ModelDownloadState'))
    ..add(DiagnosticsProperty('plan', plan))..add(DiagnosticsProperty('installedIds', installedIds))..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('currentPack', currentPack))..add(DiagnosticsProperty('currentReceivedBytes', currentReceivedBytes))..add(DiagnosticsProperty('currentTotalBytes', currentTotalBytes))..add(DiagnosticsProperty('errorMessage', errorMessage))..add(DiagnosticsProperty('placesProgressMessage', placesProgressMessage))..add(DiagnosticsProperty('placesCount', placesCount))..add(DiagnosticsProperty('tilesProgressMessage', tilesProgressMessage))..add(DiagnosticsProperty('tilesProgressFraction', tilesProgressFraction))..add(DiagnosticsProperty('tilesCached', tilesCached))..add(DiagnosticsProperty('overallFraction', overallFraction));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelDownloadState&&const DeepCollectionEquality().equals(other._plan, _plan)&&const DeepCollectionEquality().equals(other._installedIds, _installedIds)&&(identical(other.status, status) || other.status == status)&&(identical(other.currentPack, currentPack) || other.currentPack == currentPack)&&(identical(other.currentReceivedBytes, currentReceivedBytes) || other.currentReceivedBytes == currentReceivedBytes)&&(identical(other.currentTotalBytes, currentTotalBytes) || other.currentTotalBytes == currentTotalBytes)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.placesProgressMessage, placesProgressMessage) || other.placesProgressMessage == placesProgressMessage)&&(identical(other.placesCount, placesCount) || other.placesCount == placesCount)&&(identical(other.tilesProgressMessage, tilesProgressMessage) || other.tilesProgressMessage == tilesProgressMessage)&&(identical(other.tilesProgressFraction, tilesProgressFraction) || other.tilesProgressFraction == tilesProgressFraction)&&(identical(other.tilesCached, tilesCached) || other.tilesCached == tilesCached)&&(identical(other.overallFraction, overallFraction) || other.overallFraction == overallFraction));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_plan),const DeepCollectionEquality().hash(_installedIds),status,currentPack,currentReceivedBytes,currentTotalBytes,errorMessage,placesProgressMessage,placesCount,tilesProgressMessage,tilesProgressFraction,tilesCached,overallFraction);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'ModelDownloadState(plan: $plan, installedIds: $installedIds, status: $status, currentPack: $currentPack, currentReceivedBytes: $currentReceivedBytes, currentTotalBytes: $currentTotalBytes, errorMessage: $errorMessage, placesProgressMessage: $placesProgressMessage, placesCount: $placesCount, tilesProgressMessage: $tilesProgressMessage, tilesProgressFraction: $tilesProgressFraction, tilesCached: $tilesCached, overallFraction: $overallFraction)';
}


}

/// @nodoc
abstract mixin class _$ModelDownloadStateCopyWith<$Res> implements $ModelDownloadStateCopyWith<$Res> {
  factory _$ModelDownloadStateCopyWith(_ModelDownloadState value, $Res Function(_ModelDownloadState) _then) = __$ModelDownloadStateCopyWithImpl;
@override @useResult
$Res call({
 List<VoiceModelPack> plan, Set<String> installedIds, DownloadStatus status, VoiceModelPack? currentPack, int currentReceivedBytes, int currentTotalBytes, String? errorMessage, String placesProgressMessage, int placesCount, String tilesProgressMessage, double tilesProgressFraction, int tilesCached, double overallFraction
});




}
/// @nodoc
class __$ModelDownloadStateCopyWithImpl<$Res>
    implements _$ModelDownloadStateCopyWith<$Res> {
  __$ModelDownloadStateCopyWithImpl(this._self, this._then);

  final _ModelDownloadState _self;
  final $Res Function(_ModelDownloadState) _then;

/// Create a copy of ModelDownloadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? plan = null,Object? installedIds = null,Object? status = null,Object? currentPack = freezed,Object? currentReceivedBytes = null,Object? currentTotalBytes = null,Object? errorMessage = freezed,Object? placesProgressMessage = null,Object? placesCount = null,Object? tilesProgressMessage = null,Object? tilesProgressFraction = null,Object? tilesCached = null,Object? overallFraction = null,}) {
  return _then(_ModelDownloadState(
plan: null == plan ? _self._plan : plan // ignore: cast_nullable_to_non_nullable
as List<VoiceModelPack>,installedIds: null == installedIds ? _self._installedIds : installedIds // ignore: cast_nullable_to_non_nullable
as Set<String>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,currentPack: freezed == currentPack ? _self.currentPack : currentPack // ignore: cast_nullable_to_non_nullable
as VoiceModelPack?,currentReceivedBytes: null == currentReceivedBytes ? _self.currentReceivedBytes : currentReceivedBytes // ignore: cast_nullable_to_non_nullable
as int,currentTotalBytes: null == currentTotalBytes ? _self.currentTotalBytes : currentTotalBytes // ignore: cast_nullable_to_non_nullable
as int,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,placesProgressMessage: null == placesProgressMessage ? _self.placesProgressMessage : placesProgressMessage // ignore: cast_nullable_to_non_nullable
as String,placesCount: null == placesCount ? _self.placesCount : placesCount // ignore: cast_nullable_to_non_nullable
as int,tilesProgressMessage: null == tilesProgressMessage ? _self.tilesProgressMessage : tilesProgressMessage // ignore: cast_nullable_to_non_nullable
as String,tilesProgressFraction: null == tilesProgressFraction ? _self.tilesProgressFraction : tilesProgressFraction // ignore: cast_nullable_to_non_nullable
as double,tilesCached: null == tilesCached ? _self.tilesCached : tilesCached // ignore: cast_nullable_to_non_nullable
as int,overallFraction: null == overallFraction ? _self.overallFraction : overallFraction // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
