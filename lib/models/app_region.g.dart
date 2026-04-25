// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_region.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppRegion _$AppRegionFromJson(Map<String, dynamic> json) => _AppRegion(
  districtName: json['districtName'] as String,
  countryCode: json['countryCode'] as String,
  latitude: (json['latitude'] as num).toDouble(),
  longitude: (json['longitude'] as num).toDouble(),
);

Map<String, dynamic> _$AppRegionToJson(_AppRegion instance) =>
    <String, dynamic>{
      'districtName': instance.districtName,
      'countryCode': instance.countryCode,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
    };
