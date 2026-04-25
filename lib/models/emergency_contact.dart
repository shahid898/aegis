import 'package:freezed_annotation/freezed_annotation.dart';

part 'emergency_contact.freezed.dart';
part 'emergency_contact.g.dart';

@freezed
abstract class EmergencyContact with _$EmergencyContact {
  const factory EmergencyContact({
    required String id,
    required String name,
    required String phone,
    required String preferredLanguageCode,
  }) = _EmergencyContact;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      _$EmergencyContactFromJson(json);
}
