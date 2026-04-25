// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'language_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LanguageState {

 List<LanguageOption> get all; List<LanguageOption> get filtered; LanguageOption? get detected; LanguageOption? get selected; String get query; bool get isPlayingSample; String? get sampleMessage;
/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LanguageStateCopyWith<LanguageState> get copyWith => _$LanguageStateCopyWithImpl<LanguageState>(this as LanguageState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LanguageState&&const DeepCollectionEquality().equals(other.all, all)&&const DeepCollectionEquality().equals(other.filtered, filtered)&&(identical(other.detected, detected) || other.detected == detected)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.query, query) || other.query == query)&&(identical(other.isPlayingSample, isPlayingSample) || other.isPlayingSample == isPlayingSample)&&(identical(other.sampleMessage, sampleMessage) || other.sampleMessage == sampleMessage));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(all),const DeepCollectionEquality().hash(filtered),detected,selected,query,isPlayingSample,sampleMessage);

@override
String toString() {
  return 'LanguageState(all: $all, filtered: $filtered, detected: $detected, selected: $selected, query: $query, isPlayingSample: $isPlayingSample, sampleMessage: $sampleMessage)';
}


}

/// @nodoc
abstract mixin class $LanguageStateCopyWith<$Res>  {
  factory $LanguageStateCopyWith(LanguageState value, $Res Function(LanguageState) _then) = _$LanguageStateCopyWithImpl;
@useResult
$Res call({
 List<LanguageOption> all, List<LanguageOption> filtered, LanguageOption? detected, LanguageOption? selected, String query, bool isPlayingSample, String? sampleMessage
});


$LanguageOptionCopyWith<$Res>? get detected;$LanguageOptionCopyWith<$Res>? get selected;

}
/// @nodoc
class _$LanguageStateCopyWithImpl<$Res>
    implements $LanguageStateCopyWith<$Res> {
  _$LanguageStateCopyWithImpl(this._self, this._then);

  final LanguageState _self;
  final $Res Function(LanguageState) _then;

/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? all = null,Object? filtered = null,Object? detected = freezed,Object? selected = freezed,Object? query = null,Object? isPlayingSample = null,Object? sampleMessage = freezed,}) {
  return _then(_self.copyWith(
all: null == all ? _self.all : all // ignore: cast_nullable_to_non_nullable
as List<LanguageOption>,filtered: null == filtered ? _self.filtered : filtered // ignore: cast_nullable_to_non_nullable
as List<LanguageOption>,detected: freezed == detected ? _self.detected : detected // ignore: cast_nullable_to_non_nullable
as LanguageOption?,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as LanguageOption?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,isPlayingSample: null == isPlayingSample ? _self.isPlayingSample : isPlayingSample // ignore: cast_nullable_to_non_nullable
as bool,sampleMessage: freezed == sampleMessage ? _self.sampleMessage : sampleMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LanguageOptionCopyWith<$Res>? get detected {
    if (_self.detected == null) {
    return null;
  }

  return $LanguageOptionCopyWith<$Res>(_self.detected!, (value) {
    return _then(_self.copyWith(detected: value));
  });
}/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LanguageOptionCopyWith<$Res>? get selected {
    if (_self.selected == null) {
    return null;
  }

  return $LanguageOptionCopyWith<$Res>(_self.selected!, (value) {
    return _then(_self.copyWith(selected: value));
  });
}
}


/// Adds pattern-matching-related methods to [LanguageState].
extension LanguageStatePatterns on LanguageState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LanguageState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LanguageState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LanguageState value)  $default,){
final _that = this;
switch (_that) {
case _LanguageState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LanguageState value)?  $default,){
final _that = this;
switch (_that) {
case _LanguageState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<LanguageOption> all,  List<LanguageOption> filtered,  LanguageOption? detected,  LanguageOption? selected,  String query,  bool isPlayingSample,  String? sampleMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LanguageState() when $default != null:
return $default(_that.all,_that.filtered,_that.detected,_that.selected,_that.query,_that.isPlayingSample,_that.sampleMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<LanguageOption> all,  List<LanguageOption> filtered,  LanguageOption? detected,  LanguageOption? selected,  String query,  bool isPlayingSample,  String? sampleMessage)  $default,) {final _that = this;
switch (_that) {
case _LanguageState():
return $default(_that.all,_that.filtered,_that.detected,_that.selected,_that.query,_that.isPlayingSample,_that.sampleMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<LanguageOption> all,  List<LanguageOption> filtered,  LanguageOption? detected,  LanguageOption? selected,  String query,  bool isPlayingSample,  String? sampleMessage)?  $default,) {final _that = this;
switch (_that) {
case _LanguageState() when $default != null:
return $default(_that.all,_that.filtered,_that.detected,_that.selected,_that.query,_that.isPlayingSample,_that.sampleMessage);case _:
  return null;

}
}

}

/// @nodoc


class _LanguageState implements LanguageState {
  const _LanguageState({final  List<LanguageOption> all = const <LanguageOption>[], final  List<LanguageOption> filtered = const <LanguageOption>[], this.detected, this.selected, this.query = '', this.isPlayingSample = false, this.sampleMessage}): _all = all,_filtered = filtered;
  

 final  List<LanguageOption> _all;
@override@JsonKey() List<LanguageOption> get all {
  if (_all is EqualUnmodifiableListView) return _all;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_all);
}

 final  List<LanguageOption> _filtered;
@override@JsonKey() List<LanguageOption> get filtered {
  if (_filtered is EqualUnmodifiableListView) return _filtered;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_filtered);
}

@override final  LanguageOption? detected;
@override final  LanguageOption? selected;
@override@JsonKey() final  String query;
@override@JsonKey() final  bool isPlayingSample;
@override final  String? sampleMessage;

/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LanguageStateCopyWith<_LanguageState> get copyWith => __$LanguageStateCopyWithImpl<_LanguageState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LanguageState&&const DeepCollectionEquality().equals(other._all, _all)&&const DeepCollectionEquality().equals(other._filtered, _filtered)&&(identical(other.detected, detected) || other.detected == detected)&&(identical(other.selected, selected) || other.selected == selected)&&(identical(other.query, query) || other.query == query)&&(identical(other.isPlayingSample, isPlayingSample) || other.isPlayingSample == isPlayingSample)&&(identical(other.sampleMessage, sampleMessage) || other.sampleMessage == sampleMessage));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_all),const DeepCollectionEquality().hash(_filtered),detected,selected,query,isPlayingSample,sampleMessage);

@override
String toString() {
  return 'LanguageState(all: $all, filtered: $filtered, detected: $detected, selected: $selected, query: $query, isPlayingSample: $isPlayingSample, sampleMessage: $sampleMessage)';
}


}

/// @nodoc
abstract mixin class _$LanguageStateCopyWith<$Res> implements $LanguageStateCopyWith<$Res> {
  factory _$LanguageStateCopyWith(_LanguageState value, $Res Function(_LanguageState) _then) = __$LanguageStateCopyWithImpl;
@override @useResult
$Res call({
 List<LanguageOption> all, List<LanguageOption> filtered, LanguageOption? detected, LanguageOption? selected, String query, bool isPlayingSample, String? sampleMessage
});


@override $LanguageOptionCopyWith<$Res>? get detected;@override $LanguageOptionCopyWith<$Res>? get selected;

}
/// @nodoc
class __$LanguageStateCopyWithImpl<$Res>
    implements _$LanguageStateCopyWith<$Res> {
  __$LanguageStateCopyWithImpl(this._self, this._then);

  final _LanguageState _self;
  final $Res Function(_LanguageState) _then;

/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? all = null,Object? filtered = null,Object? detected = freezed,Object? selected = freezed,Object? query = null,Object? isPlayingSample = null,Object? sampleMessage = freezed,}) {
  return _then(_LanguageState(
all: null == all ? _self._all : all // ignore: cast_nullable_to_non_nullable
as List<LanguageOption>,filtered: null == filtered ? _self._filtered : filtered // ignore: cast_nullable_to_non_nullable
as List<LanguageOption>,detected: freezed == detected ? _self.detected : detected // ignore: cast_nullable_to_non_nullable
as LanguageOption?,selected: freezed == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as LanguageOption?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,isPlayingSample: null == isPlayingSample ? _self.isPlayingSample : isPlayingSample // ignore: cast_nullable_to_non_nullable
as bool,sampleMessage: freezed == sampleMessage ? _self.sampleMessage : sampleMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LanguageOptionCopyWith<$Res>? get detected {
    if (_self.detected == null) {
    return null;
  }

  return $LanguageOptionCopyWith<$Res>(_self.detected!, (value) {
    return _then(_self.copyWith(detected: value));
  });
}/// Create a copy of LanguageState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LanguageOptionCopyWith<$Res>? get selected {
    if (_self.selected == null) {
    return null;
  }

  return $LanguageOptionCopyWith<$Res>(_self.selected!, (value) {
    return _then(_self.copyWith(selected: value));
  });
}
}

// dart format on
