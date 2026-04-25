// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accessibility_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AccessibilityProfile _$AccessibilityProfileFromJson(
  Map<String, dynamic> json,
) => _AccessibilityProfile(
  usesWheelchair: json['usesWheelchair'] as bool? ?? false,
  takesDailyMedication: json['takesDailyMedication'] as bool? ?? false,
  hasDependent: json['hasDependent'] as bool? ?? false,
);

Map<String, dynamic> _$AccessibilityProfileToJson(
  _AccessibilityProfile instance,
) => <String, dynamic>{
  'usesWheelchair': instance.usesWheelchair,
  'takesDailyMedication': instance.takesDailyMedication,
  'hasDependent': instance.hasDependent,
};
