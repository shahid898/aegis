// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'assistant_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AssistantState implements DiagnosticableTreeMixin {

 AssistantStage get stage; String get transcript; String get response; List<ConversationTurn> get turns; bool get surfaceReady; String get thinkingTrace; String? get errorMessage; Uint8List? get pendingUserImage; Uint8List? get pendingUserAudio; bool get intakeOpen; String get intakeText; bool get intakeHasPhoto; bool get intakeHasAudio; bool get thinkingForReport; Uint8List? get intakeImagePreview; String? get languageCode;/// True while the LLM engine is paying its first-run cold-start
/// cost (shader compile + KV-cache prefill, 10-30 s on Mali/Adreno
/// GPUs). Drives the home page's "Preparing AI engine…" overlay.
 bool get engineWarming;
/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AssistantStateCopyWith<AssistantState> get copyWith => _$AssistantStateCopyWithImpl<AssistantState>(this as AssistantState, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AssistantState'))
    ..add(DiagnosticsProperty('stage', stage))..add(DiagnosticsProperty('transcript', transcript))..add(DiagnosticsProperty('response', response))..add(DiagnosticsProperty('turns', turns))..add(DiagnosticsProperty('surfaceReady', surfaceReady))..add(DiagnosticsProperty('thinkingTrace', thinkingTrace))..add(DiagnosticsProperty('errorMessage', errorMessage))..add(DiagnosticsProperty('pendingUserImage', pendingUserImage))..add(DiagnosticsProperty('pendingUserAudio', pendingUserAudio))..add(DiagnosticsProperty('intakeOpen', intakeOpen))..add(DiagnosticsProperty('intakeText', intakeText))..add(DiagnosticsProperty('intakeHasPhoto', intakeHasPhoto))..add(DiagnosticsProperty('intakeHasAudio', intakeHasAudio))..add(DiagnosticsProperty('thinkingForReport', thinkingForReport))..add(DiagnosticsProperty('intakeImagePreview', intakeImagePreview))..add(DiagnosticsProperty('languageCode', languageCode))..add(DiagnosticsProperty('engineWarming', engineWarming));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssistantState&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.transcript, transcript) || other.transcript == transcript)&&(identical(other.response, response) || other.response == response)&&const DeepCollectionEquality().equals(other.turns, turns)&&(identical(other.surfaceReady, surfaceReady) || other.surfaceReady == surfaceReady)&&(identical(other.thinkingTrace, thinkingTrace) || other.thinkingTrace == thinkingTrace)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&const DeepCollectionEquality().equals(other.pendingUserImage, pendingUserImage)&&const DeepCollectionEquality().equals(other.pendingUserAudio, pendingUserAudio)&&(identical(other.intakeOpen, intakeOpen) || other.intakeOpen == intakeOpen)&&(identical(other.intakeText, intakeText) || other.intakeText == intakeText)&&(identical(other.intakeHasPhoto, intakeHasPhoto) || other.intakeHasPhoto == intakeHasPhoto)&&(identical(other.intakeHasAudio, intakeHasAudio) || other.intakeHasAudio == intakeHasAudio)&&(identical(other.thinkingForReport, thinkingForReport) || other.thinkingForReport == thinkingForReport)&&const DeepCollectionEquality().equals(other.intakeImagePreview, intakeImagePreview)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.engineWarming, engineWarming) || other.engineWarming == engineWarming));
}


@override
int get hashCode => Object.hash(runtimeType,stage,transcript,response,const DeepCollectionEquality().hash(turns),surfaceReady,thinkingTrace,errorMessage,const DeepCollectionEquality().hash(pendingUserImage),const DeepCollectionEquality().hash(pendingUserAudio),intakeOpen,intakeText,intakeHasPhoto,intakeHasAudio,thinkingForReport,const DeepCollectionEquality().hash(intakeImagePreview),languageCode,engineWarming);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AssistantState(stage: $stage, transcript: $transcript, response: $response, turns: $turns, surfaceReady: $surfaceReady, thinkingTrace: $thinkingTrace, errorMessage: $errorMessage, pendingUserImage: $pendingUserImage, pendingUserAudio: $pendingUserAudio, intakeOpen: $intakeOpen, intakeText: $intakeText, intakeHasPhoto: $intakeHasPhoto, intakeHasAudio: $intakeHasAudio, thinkingForReport: $thinkingForReport, intakeImagePreview: $intakeImagePreview, languageCode: $languageCode, engineWarming: $engineWarming)';
}


}

/// @nodoc
abstract mixin class $AssistantStateCopyWith<$Res>  {
  factory $AssistantStateCopyWith(AssistantState value, $Res Function(AssistantState) _then) = _$AssistantStateCopyWithImpl;
@useResult
$Res call({
 AssistantStage stage, String transcript, String response, List<ConversationTurn> turns, bool surfaceReady, String thinkingTrace, String? errorMessage, Uint8List? pendingUserImage, Uint8List? pendingUserAudio, bool intakeOpen, String intakeText, bool intakeHasPhoto, bool intakeHasAudio, bool thinkingForReport, Uint8List? intakeImagePreview, String? languageCode, bool engineWarming
});




}
/// @nodoc
class _$AssistantStateCopyWithImpl<$Res>
    implements $AssistantStateCopyWith<$Res> {
  _$AssistantStateCopyWithImpl(this._self, this._then);

  final AssistantState _self;
  final $Res Function(AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stage = null,Object? transcript = null,Object? response = null,Object? turns = null,Object? surfaceReady = null,Object? thinkingTrace = null,Object? errorMessage = freezed,Object? pendingUserImage = freezed,Object? pendingUserAudio = freezed,Object? intakeOpen = null,Object? intakeText = null,Object? intakeHasPhoto = null,Object? intakeHasAudio = null,Object? thinkingForReport = null,Object? intakeImagePreview = freezed,Object? languageCode = freezed,Object? engineWarming = null,}) {
  return _then(_self.copyWith(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as AssistantStage,transcript: null == transcript ? _self.transcript : transcript // ignore: cast_nullable_to_non_nullable
as String,response: null == response ? _self.response : response // ignore: cast_nullable_to_non_nullable
as String,turns: null == turns ? _self.turns : turns // ignore: cast_nullable_to_non_nullable
as List<ConversationTurn>,surfaceReady: null == surfaceReady ? _self.surfaceReady : surfaceReady // ignore: cast_nullable_to_non_nullable
as bool,thinkingTrace: null == thinkingTrace ? _self.thinkingTrace : thinkingTrace // ignore: cast_nullable_to_non_nullable
as String,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,pendingUserImage: freezed == pendingUserImage ? _self.pendingUserImage : pendingUserImage // ignore: cast_nullable_to_non_nullable
as Uint8List?,pendingUserAudio: freezed == pendingUserAudio ? _self.pendingUserAudio : pendingUserAudio // ignore: cast_nullable_to_non_nullable
as Uint8List?,intakeOpen: null == intakeOpen ? _self.intakeOpen : intakeOpen // ignore: cast_nullable_to_non_nullable
as bool,intakeText: null == intakeText ? _self.intakeText : intakeText // ignore: cast_nullable_to_non_nullable
as String,intakeHasPhoto: null == intakeHasPhoto ? _self.intakeHasPhoto : intakeHasPhoto // ignore: cast_nullable_to_non_nullable
as bool,intakeHasAudio: null == intakeHasAudio ? _self.intakeHasAudio : intakeHasAudio // ignore: cast_nullable_to_non_nullable
as bool,thinkingForReport: null == thinkingForReport ? _self.thinkingForReport : thinkingForReport // ignore: cast_nullable_to_non_nullable
as bool,intakeImagePreview: freezed == intakeImagePreview ? _self.intakeImagePreview : intakeImagePreview // ignore: cast_nullable_to_non_nullable
as Uint8List?,languageCode: freezed == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String?,engineWarming: null == engineWarming ? _self.engineWarming : engineWarming // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AssistantState].
extension AssistantStatePatterns on AssistantState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssistantState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssistantState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssistantState value)  $default,){
final _that = this;
switch (_that) {
case _AssistantState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssistantState value)?  $default,){
final _that = this;
switch (_that) {
case _AssistantState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AssistantStage stage,  String transcript,  String response,  List<ConversationTurn> turns,  bool surfaceReady,  String thinkingTrace,  String? errorMessage,  Uint8List? pendingUserImage,  Uint8List? pendingUserAudio,  bool intakeOpen,  String intakeText,  bool intakeHasPhoto,  bool intakeHasAudio,  bool thinkingForReport,  Uint8List? intakeImagePreview,  String? languageCode,  bool engineWarming)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssistantState() when $default != null:
return $default(_that.stage,_that.transcript,_that.response,_that.turns,_that.surfaceReady,_that.thinkingTrace,_that.errorMessage,_that.pendingUserImage,_that.pendingUserAudio,_that.intakeOpen,_that.intakeText,_that.intakeHasPhoto,_that.intakeHasAudio,_that.thinkingForReport,_that.intakeImagePreview,_that.languageCode,_that.engineWarming);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AssistantStage stage,  String transcript,  String response,  List<ConversationTurn> turns,  bool surfaceReady,  String thinkingTrace,  String? errorMessage,  Uint8List? pendingUserImage,  Uint8List? pendingUserAudio,  bool intakeOpen,  String intakeText,  bool intakeHasPhoto,  bool intakeHasAudio,  bool thinkingForReport,  Uint8List? intakeImagePreview,  String? languageCode,  bool engineWarming)  $default,) {final _that = this;
switch (_that) {
case _AssistantState():
return $default(_that.stage,_that.transcript,_that.response,_that.turns,_that.surfaceReady,_that.thinkingTrace,_that.errorMessage,_that.pendingUserImage,_that.pendingUserAudio,_that.intakeOpen,_that.intakeText,_that.intakeHasPhoto,_that.intakeHasAudio,_that.thinkingForReport,_that.intakeImagePreview,_that.languageCode,_that.engineWarming);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AssistantStage stage,  String transcript,  String response,  List<ConversationTurn> turns,  bool surfaceReady,  String thinkingTrace,  String? errorMessage,  Uint8List? pendingUserImage,  Uint8List? pendingUserAudio,  bool intakeOpen,  String intakeText,  bool intakeHasPhoto,  bool intakeHasAudio,  bool thinkingForReport,  Uint8List? intakeImagePreview,  String? languageCode,  bool engineWarming)?  $default,) {final _that = this;
switch (_that) {
case _AssistantState() when $default != null:
return $default(_that.stage,_that.transcript,_that.response,_that.turns,_that.surfaceReady,_that.thinkingTrace,_that.errorMessage,_that.pendingUserImage,_that.pendingUserAudio,_that.intakeOpen,_that.intakeText,_that.intakeHasPhoto,_that.intakeHasAudio,_that.thinkingForReport,_that.intakeImagePreview,_that.languageCode,_that.engineWarming);case _:
  return null;

}
}

}

/// @nodoc


class _AssistantState extends AssistantState with DiagnosticableTreeMixin {
  const _AssistantState({this.stage = AssistantStage.idle, this.transcript = '', this.response = '', final  List<ConversationTurn> turns = const <ConversationTurn>[], this.surfaceReady = false, this.thinkingTrace = '', this.errorMessage, this.pendingUserImage, this.pendingUserAudio, this.intakeOpen = false, this.intakeText = '', this.intakeHasPhoto = false, this.intakeHasAudio = false, this.thinkingForReport = false, this.intakeImagePreview, this.languageCode, this.engineWarming = false}): _turns = turns,super._();
  

@override@JsonKey() final  AssistantStage stage;
@override@JsonKey() final  String transcript;
@override@JsonKey() final  String response;
 final  List<ConversationTurn> _turns;
@override@JsonKey() List<ConversationTurn> get turns {
  if (_turns is EqualUnmodifiableListView) return _turns;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_turns);
}

@override@JsonKey() final  bool surfaceReady;
@override@JsonKey() final  String thinkingTrace;
@override final  String? errorMessage;
@override final  Uint8List? pendingUserImage;
@override final  Uint8List? pendingUserAudio;
@override@JsonKey() final  bool intakeOpen;
@override@JsonKey() final  String intakeText;
@override@JsonKey() final  bool intakeHasPhoto;
@override@JsonKey() final  bool intakeHasAudio;
@override@JsonKey() final  bool thinkingForReport;
@override final  Uint8List? intakeImagePreview;
@override final  String? languageCode;
/// True while the LLM engine is paying its first-run cold-start
/// cost (shader compile + KV-cache prefill, 10-30 s on Mali/Adreno
/// GPUs). Drives the home page's "Preparing AI engine…" overlay.
@override@JsonKey() final  bool engineWarming;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AssistantStateCopyWith<_AssistantState> get copyWith => __$AssistantStateCopyWithImpl<_AssistantState>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AssistantState'))
    ..add(DiagnosticsProperty('stage', stage))..add(DiagnosticsProperty('transcript', transcript))..add(DiagnosticsProperty('response', response))..add(DiagnosticsProperty('turns', turns))..add(DiagnosticsProperty('surfaceReady', surfaceReady))..add(DiagnosticsProperty('thinkingTrace', thinkingTrace))..add(DiagnosticsProperty('errorMessage', errorMessage))..add(DiagnosticsProperty('pendingUserImage', pendingUserImage))..add(DiagnosticsProperty('pendingUserAudio', pendingUserAudio))..add(DiagnosticsProperty('intakeOpen', intakeOpen))..add(DiagnosticsProperty('intakeText', intakeText))..add(DiagnosticsProperty('intakeHasPhoto', intakeHasPhoto))..add(DiagnosticsProperty('intakeHasAudio', intakeHasAudio))..add(DiagnosticsProperty('thinkingForReport', thinkingForReport))..add(DiagnosticsProperty('intakeImagePreview', intakeImagePreview))..add(DiagnosticsProperty('languageCode', languageCode))..add(DiagnosticsProperty('engineWarming', engineWarming));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssistantState&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.transcript, transcript) || other.transcript == transcript)&&(identical(other.response, response) || other.response == response)&&const DeepCollectionEquality().equals(other._turns, _turns)&&(identical(other.surfaceReady, surfaceReady) || other.surfaceReady == surfaceReady)&&(identical(other.thinkingTrace, thinkingTrace) || other.thinkingTrace == thinkingTrace)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&const DeepCollectionEquality().equals(other.pendingUserImage, pendingUserImage)&&const DeepCollectionEquality().equals(other.pendingUserAudio, pendingUserAudio)&&(identical(other.intakeOpen, intakeOpen) || other.intakeOpen == intakeOpen)&&(identical(other.intakeText, intakeText) || other.intakeText == intakeText)&&(identical(other.intakeHasPhoto, intakeHasPhoto) || other.intakeHasPhoto == intakeHasPhoto)&&(identical(other.intakeHasAudio, intakeHasAudio) || other.intakeHasAudio == intakeHasAudio)&&(identical(other.thinkingForReport, thinkingForReport) || other.thinkingForReport == thinkingForReport)&&const DeepCollectionEquality().equals(other.intakeImagePreview, intakeImagePreview)&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.engineWarming, engineWarming) || other.engineWarming == engineWarming));
}


@override
int get hashCode => Object.hash(runtimeType,stage,transcript,response,const DeepCollectionEquality().hash(_turns),surfaceReady,thinkingTrace,errorMessage,const DeepCollectionEquality().hash(pendingUserImage),const DeepCollectionEquality().hash(pendingUserAudio),intakeOpen,intakeText,intakeHasPhoto,intakeHasAudio,thinkingForReport,const DeepCollectionEquality().hash(intakeImagePreview),languageCode,engineWarming);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AssistantState(stage: $stage, transcript: $transcript, response: $response, turns: $turns, surfaceReady: $surfaceReady, thinkingTrace: $thinkingTrace, errorMessage: $errorMessage, pendingUserImage: $pendingUserImage, pendingUserAudio: $pendingUserAudio, intakeOpen: $intakeOpen, intakeText: $intakeText, intakeHasPhoto: $intakeHasPhoto, intakeHasAudio: $intakeHasAudio, thinkingForReport: $thinkingForReport, intakeImagePreview: $intakeImagePreview, languageCode: $languageCode, engineWarming: $engineWarming)';
}


}

/// @nodoc
abstract mixin class _$AssistantStateCopyWith<$Res> implements $AssistantStateCopyWith<$Res> {
  factory _$AssistantStateCopyWith(_AssistantState value, $Res Function(_AssistantState) _then) = __$AssistantStateCopyWithImpl;
@override @useResult
$Res call({
 AssistantStage stage, String transcript, String response, List<ConversationTurn> turns, bool surfaceReady, String thinkingTrace, String? errorMessage, Uint8List? pendingUserImage, Uint8List? pendingUserAudio, bool intakeOpen, String intakeText, bool intakeHasPhoto, bool intakeHasAudio, bool thinkingForReport, Uint8List? intakeImagePreview, String? languageCode, bool engineWarming
});




}
/// @nodoc
class __$AssistantStateCopyWithImpl<$Res>
    implements _$AssistantStateCopyWith<$Res> {
  __$AssistantStateCopyWithImpl(this._self, this._then);

  final _AssistantState _self;
  final $Res Function(_AssistantState) _then;

/// Create a copy of AssistantState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stage = null,Object? transcript = null,Object? response = null,Object? turns = null,Object? surfaceReady = null,Object? thinkingTrace = null,Object? errorMessage = freezed,Object? pendingUserImage = freezed,Object? pendingUserAudio = freezed,Object? intakeOpen = null,Object? intakeText = null,Object? intakeHasPhoto = null,Object? intakeHasAudio = null,Object? thinkingForReport = null,Object? intakeImagePreview = freezed,Object? languageCode = freezed,Object? engineWarming = null,}) {
  return _then(_AssistantState(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as AssistantStage,transcript: null == transcript ? _self.transcript : transcript // ignore: cast_nullable_to_non_nullable
as String,response: null == response ? _self.response : response // ignore: cast_nullable_to_non_nullable
as String,turns: null == turns ? _self._turns : turns // ignore: cast_nullable_to_non_nullable
as List<ConversationTurn>,surfaceReady: null == surfaceReady ? _self.surfaceReady : surfaceReady // ignore: cast_nullable_to_non_nullable
as bool,thinkingTrace: null == thinkingTrace ? _self.thinkingTrace : thinkingTrace // ignore: cast_nullable_to_non_nullable
as String,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,pendingUserImage: freezed == pendingUserImage ? _self.pendingUserImage : pendingUserImage // ignore: cast_nullable_to_non_nullable
as Uint8List?,pendingUserAudio: freezed == pendingUserAudio ? _self.pendingUserAudio : pendingUserAudio // ignore: cast_nullable_to_non_nullable
as Uint8List?,intakeOpen: null == intakeOpen ? _self.intakeOpen : intakeOpen // ignore: cast_nullable_to_non_nullable
as bool,intakeText: null == intakeText ? _self.intakeText : intakeText // ignore: cast_nullable_to_non_nullable
as String,intakeHasPhoto: null == intakeHasPhoto ? _self.intakeHasPhoto : intakeHasPhoto // ignore: cast_nullable_to_non_nullable
as bool,intakeHasAudio: null == intakeHasAudio ? _self.intakeHasAudio : intakeHasAudio // ignore: cast_nullable_to_non_nullable
as bool,thinkingForReport: null == thinkingForReport ? _self.thinkingForReport : thinkingForReport // ignore: cast_nullable_to_non_nullable
as bool,intakeImagePreview: freezed == intakeImagePreview ? _self.intakeImagePreview : intakeImagePreview // ignore: cast_nullable_to_non_nullable
as Uint8List?,languageCode: freezed == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String?,engineWarming: null == engineWarming ? _self.engineWarming : engineWarming // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
