import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/constants/languages.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/voice/model_catalog.dart';
import '../../../../core/voice/model_registry.dart';
import '../../../../core/voice/tts_service.dart';
import '../../../../models/language_option.dart';

part 'language_cubit.freezed.dart';

@freezed
abstract class LanguageState with _$LanguageState {
  const factory LanguageState({
    @Default(<LanguageOption>[]) List<LanguageOption> all,
    @Default(<LanguageOption>[]) List<LanguageOption> filtered,
    LanguageOption? detected,
    LanguageOption? selected,
    @Default('') String query,
    @Default(false) bool isPlayingSample,
    String? sampleMessage,
  }) = _LanguageState;
}

/// Short greeting per language used for the "hear sample" button. Falls
/// back to English when the language isn't in the map.
const Map<String, String> _samplePhrases = {
  'en': 'Hello. Aegis is ready to help you.',
  'hi': 'नमस्ते। एजिस आपकी सहायता के लिए तैयार है।',
  'es': 'Hola. Aegis está listo para ayudarte.',
  'fr': 'Bonjour. Aegis est prêt à vous aider.',
  'de': 'Hallo. Aegis ist bereit, Ihnen zu helfen.',
  'it': 'Ciao. Aegis è pronto ad aiutarti.',
  'pt': 'Olá. O Aegis está pronto para ajudar.',
  'ru': 'Здравствуйте. Aegis готов помочь.',
  'tr': 'Merhaba. Aegis size yardım etmeye hazır.',
  'ar': 'مرحبا. إيجيس جاهز لمساعدتك.',
};

class LanguageCubit extends Cubit<LanguageState> {
  LanguageCubit(this._storage, this._tts, this._registry)
      : super(const LanguageState()) {
    _bootstrap();
  }

  final StorageService _storage;
  final TtsService _tts;
  final ModelRegistry _registry;

  void _bootstrap() {
    final all = SupportedLanguages.all;
    final systemCode = PlatformDispatcher.instance.locale.languageCode;
    final detected = all.firstWhere(
      (l) => l.code == systemCode,
      orElse: () => all.first,
    );
    final savedCode = _storage.selectedLanguageCode;
    final selected = savedCode != null
        ? all.firstWhere((l) => l.code == savedCode, orElse: () => detected)
        : detected;

    emit(state.copyWith(
      all: all,
      filtered: all,
      detected: detected,
      selected: selected,
    ));
  }

  void search(String query) {
    final trimmed = query.trim().toLowerCase();
    final filtered = trimmed.isEmpty
        ? state.all
        : state.all.where((l) {
            return l.englishName.toLowerCase().contains(trimmed) ||
                l.nativeName.toLowerCase().contains(trimmed) ||
                l.code.toLowerCase().contains(trimmed);
          }).toList();
    emit(state.copyWith(query: query, filtered: filtered));
  }

  void select(LanguageOption option) {
    emit(state.copyWith(selected: option));
  }

  Future<void> confirm() async {
    final selected = state.selected;
    if (selected == null) return;
    await _storage.setSelectedLanguageCode(selected.code);
  }

  /// Play a short sample phrase in [option]'s language if a matching TTS
  /// pack is installed. Silently degrades to a helpful banner if the
  /// voice pack hasn't been downloaded yet.
  Future<void> playSample(LanguageOption option) async {
    final pack = ModelCatalog.ttsForLanguage(option.code);
    if (pack == null) {
      emit(state.copyWith(
        sampleMessage:
            'No offline voice available for ${option.englishName}.',
      ));
      return;
    }
    if (!await _registry.isInstalled(pack)) {
      emit(state.copyWith(
        sampleMessage:
            'Voice for ${option.englishName} will be ready after download.',
      ));
      return;
    }

    try {
      emit(state.copyWith(
        isPlayingSample: true,
        sampleMessage: null,
      ));
      await _tts.load(pack);
      final phrase =
          _samplePhrases[option.code] ?? _samplePhrases['en']!;
      await _tts.speak(phrase);
    } catch (e) {
      emit(state.copyWith(
        sampleMessage: 'Could not play sample: $e',
      ));
    } finally {
      emit(state.copyWith(isPlayingSample: false));
    }
  }
}
