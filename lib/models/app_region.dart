import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_region.freezed.dart';
part 'app_region.g.dart';

@freezed
abstract class AppRegion with _$AppRegion {
  const factory AppRegion({
    required String districtName,
    required String countryCode,
    required double latitude,
    required double longitude,
  }) = _AppRegion;

  factory AppRegion.fromJson(Map<String, dynamic> json) =>
      _$AppRegionFromJson(json);
}
