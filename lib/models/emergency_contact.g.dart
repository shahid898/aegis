// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emergency_contact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_EmergencyContact _$EmergencyContactFromJson(Map<String, dynamic> json) =>
    _EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      preferredLanguageCode: json['preferredLanguageCode'] as String,
    );

Map<String, dynamic> _$EmergencyContactToJson(_EmergencyContact instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'phone': instance.phone,
      'preferredLanguageCode': instance.preferredLanguageCode,
    };
