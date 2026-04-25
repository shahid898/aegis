import 'package:freezed_annotation/freezed_annotation.dart';

part 'accessibility_profile.freezed.dart';
part 'accessibility_profile.g.dart';

@freezed
abstract class AccessibilityProfile with _$AccessibilityProfile {
  const factory AccessibilityProfile({
    @Default(false) bool usesWheelchair,
    @Default(false) bool takesDailyMedication,
    @Default(false) bool hasDependent,
  }) = _AccessibilityProfile;

  factory AccessibilityProfile.fromJson(Map<String, dynamic> json) =>
      _$AccessibilityProfileFromJson(json);
}
