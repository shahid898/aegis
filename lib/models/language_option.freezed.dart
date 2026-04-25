// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'language_option.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LanguageOption {

 String get code; String get englishName; String get nativeName;
/// Create a copy of LanguageOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LanguageOptionCopyWith<LanguageOption> get copyWith => _$LanguageOptionCopyWithImpl<LanguageOption>(this as LanguageOption, _$identity);

  /// Serializes this LanguageOption to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LanguageOption&&(identical(other.code, code) || other.code == code)&&(identical(other.englishName, englishName) || other.englishName == englishName)&&(identical(other.nativeName, nativeName) || other.nativeName == nativeName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,englishName,nativeName);

@override
String toString() {
  return 'LanguageOption(code: $code, englishName: $englishName, nativeName: $nativeName)';
}


}

/// @nodoc
abstract mixin class $LanguageOptionCopyWith<$Res>  {
  factory $LanguageOptionCopyWith(LanguageOption value, $Res Function(LanguageOption) _then) = _$LanguageOptionCopyWithImpl;
@useResult
$Res call({
 String code, String englishName, String nativeName
});




}
/// @nodoc
class _$LanguageOptionCopyWithImpl<$Res>
    implements $LanguageOptionCopyWith<$Res> {
  _$LanguageOptionCopyWithImpl(this._self, this._then);

  final LanguageOption _self;
  final $Res Function(LanguageOption) _then;

/// Create a copy of LanguageOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? englishName = null,Object? nativeName = null,}) {
  return _then(_self.copyWith(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,englishName: null == englishName ? _self.englishName : englishName // ignore: cast_nullable_to_non_nullable
as String,nativeName: null == nativeName ? _self.nativeName : nativeName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LanguageOption].
extension LanguageOptionPatterns on LanguageOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LanguageOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LanguageOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LanguageOption value)  $default,){
final _that = this;
switch (_that) {
case _LanguageOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LanguageOption value)?  $default,){
final _that = this;
switch (_that) {
case _LanguageOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String englishName,  String nativeName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LanguageOption() when $default != null:
return $default(_that.code,_that.englishName,_that.nativeName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String englishName,  String nativeName)  $default,) {final _that = this;
switch (_that) {
case _LanguageOption():
return $default(_that.code,_that.englishName,_that.nativeName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String englishName,  String nativeName)?  $default,) {final _that = this;
switch (_that) {
case _LanguageOption() when $default != null:
return $default(_that.code,_that.englishName,_that.nativeName);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LanguageOption implements LanguageOption {
  const _LanguageOption({required this.code, required this.englishName, required this.nativeName});
  factory _LanguageOption.fromJson(Map<String, dynamic> json) => _$LanguageOptionFromJson(json);

@override final  String code;
@override final  String englishName;
@override final  String nativeName;

/// Create a copy of LanguageOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LanguageOptionCopyWith<_LanguageOption> get copyWith => __$LanguageOptionCopyWithImpl<_LanguageOption>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LanguageOptionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LanguageOption&&(identical(other.code, code) || other.code == code)&&(identical(other.englishName, englishName) || other.englishName == englishName)&&(identical(other.nativeName, nativeName) || other.nativeName == nativeName));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,code,englishName,nativeName);

@override
String toString() {
  return 'LanguageOption(code: $code, englishName: $englishName, nativeName: $nativeName)';
}


}

/// @nodoc
abstract mixin class _$LanguageOptionCopyWith<$Res> implements $LanguageOptionCopyWith<$Res> {
  factory _$LanguageOptionCopyWith(_LanguageOption value, $Res Function(_LanguageOption) _then) = __$LanguageOptionCopyWithImpl;
@override @useResult
$Res call({
 String code, String englishName, String nativeName
});




}
/// @nodoc
class __$LanguageOptionCopyWithImpl<$Res>
    implements _$LanguageOptionCopyWith<$Res> {
  __$LanguageOptionCopyWithImpl(this._self, this._then);

  final _LanguageOption _self;
  final $Res Function(_LanguageOption) _then;

/// Create a copy of LanguageOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? englishName = null,Object? nativeName = null,}) {
  return _then(_LanguageOption(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,englishName: null == englishName ? _self.englishName : englishName // ignore: cast_nullable_to_non_nullable
as String,nativeName: null == nativeName ? _self.nativeName : nativeName // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
