import 'package:freezed_annotation/freezed_annotation.dart';

part 'language_option.freezed.dart';
part 'language_option.g.dart';

@freezed
abstract class LanguageOption with _$LanguageOption {
  const factory LanguageOption({
    required String code,
    required String englishName,
    required String nativeName,
  }) = _LanguageOption;

  factory LanguageOption.fromJson(Map<String, dynamic> json) =>
      _$LanguageOptionFromJson(json);
}
