import 'model_pack.dart';

/// Static catalog of voice model packs keyed by country code.
///
/// URLs point at the sherpa-onnx release assets on GitHub:
///   https://github.com/k2-fsa/sherpa-onnx/releases
///
/// SHA-256 values intentionally left blank for the initial scaffold.
/// Before release, populate them with the values published alongside each
/// asset (the repository refuses to mark a pack "installed" if SHA mismatch
/// once the field is non-empty).
///
/// Sizes are approximate, used only for the progress UI. The actual
/// download size is taken from the HTTP Content-Length header.
class ModelCatalog {
  ModelCatalog._();

  // ---------------------------------------------------------------------------
  // VAD: Silero v5 voice activity detector. Single ~2 MB onnx file fetched
  // directly (no archive). The VAD listens to the mic and emits speech
  // segments to feed into Whisper.
  //   https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/
  //   silero_vad.onnx
  //
  // The pack reuses ModelKind.stt (no separate VAD kind exists yet) but
  // is plumbed through a dedicated SttService.setVadPack() so the runtime
  // never confuses it with a real recognizer.
  // ---------------------------------------------------------------------------
  static const VoiceModelPack _sileroVad = VoiceModelPack(
    id: 'vad-silero-v5',
    kind: ModelKind.stt,
    displayName: 'Voice activity detector',
    // VAD is language-agnostic; list the most common codes so the
    // language-aware pack picker won't reject it.
    languageCodes: _allLanguageCodes,
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
    archiveSha256: '',
    approxBytes: 2 * 1024 * 1024,
    rootDirName: 'silero-vad',
    modelFile: ModelFile(relativePath: 'silero_vad.onnx'),
    isArchive: false,
  );

  // ---------------------------------------------------------------------------
  // Piper TTS packs — one per language/voice. Each bundle ships an
  // `espeak-ng-data` directory which sherpa expects as `dataDir`.
  // ---------------------------------------------------------------------------

  static const VoiceModelPack _ttsPiperEnUsLessac = VoiceModelPack(
    id: 'tts-piper-en_US-lessac',
    kind: ModelKind.tts,
    displayName: 'English (US) voice',
    languageCodes: ['en'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-en_US-lessac-medium',
    modelFile: ModelFile(relativePath: 'en_US-lessac-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperEnGbAlan = VoiceModelPack(
    id: 'tts-piper-en_GB-alan',
    kind: ModelKind.tts,
    displayName: 'English (UK) voice',
    languageCodes: ['en'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alan-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-en_GB-alan-medium',
    modelFile: ModelFile(relativePath: 'en_GB-alan-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperHiInPratham = VoiceModelPack(
    id: 'tts-piper-hi_IN-pratham',
    kind: ModelKind.tts,
    displayName: 'Hindi voice',
    languageCodes: ['hi'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-hi_IN-pratham-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-hi_IN-pratham-medium',
    modelFile: ModelFile(relativePath: 'hi_IN-pratham-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperEsEsDavefx = VoiceModelPack(
    id: 'tts-piper-es_ES-davefx',
    kind: ModelKind.tts,
    displayName: 'Spanish voice',
    languageCodes: ['es'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-davefx-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-es_ES-davefx-medium',
    modelFile: ModelFile(relativePath: 'es_ES-davefx-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperFrFrSiwis = VoiceModelPack(
    id: 'tts-piper-fr_FR-siwis',
    kind: ModelKind.tts,
    displayName: 'French voice',
    languageCodes: ['fr'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-siwis-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-fr_FR-siwis-medium',
    modelFile: ModelFile(relativePath: 'fr_FR-siwis-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperDeDeThorsten = VoiceModelPack(
    id: 'tts-piper-de_DE-thorsten',
    kind: ModelKind.tts,
    displayName: 'German voice',
    languageCodes: ['de'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-de_DE-thorsten-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-de_DE-thorsten-medium',
    modelFile: ModelFile(relativePath: 'de_DE-thorsten-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperPtBrFaber = VoiceModelPack(
    id: 'tts-piper-pt_BR-faber',
    kind: ModelKind.tts,
    displayName: 'Portuguese (BR) voice',
    languageCodes: ['pt'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_BR-faber-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-pt_BR-faber-medium',
    modelFile: ModelFile(relativePath: 'pt_BR-faber-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperItItRiccardo = VoiceModelPack(
    id: 'tts-piper-it_IT-riccardo',
    kind: ModelKind.tts,
    displayName: 'Italian voice',
    languageCodes: ['it'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-it_IT-riccardo-x_low.tar.bz2',
    archiveSha256: '',
    approxBytes: 30 * 1024 * 1024,
    rootDirName: 'vits-piper-it_IT-riccardo-x_low',
    modelFile: ModelFile(relativePath: 'it_IT-riccardo-x_low.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 16000,
  );

  static const VoiceModelPack _ttsPiperRuRuDenis = VoiceModelPack(
    id: 'tts-piper-ru_RU-denis',
    kind: ModelKind.tts,
    displayName: 'Russian voice',
    languageCodes: ['ru'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-denis-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-ru_RU-denis-medium',
    modelFile: ModelFile(relativePath: 'ru_RU-denis-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperTrTrDfki = VoiceModelPack(
    id: 'tts-piper-tr_TR-dfki',
    kind: ModelKind.tts,
    displayName: 'Turkish voice',
    languageCodes: ['tr'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-tr_TR-dfki-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-tr_TR-dfki-medium',
    modelFile: ModelFile(relativePath: 'tr_TR-dfki-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  static const VoiceModelPack _ttsPiperArJoXkadir = VoiceModelPack(
    id: 'tts-piper-ar_JO-kareem',
    kind: ModelKind.tts,
    displayName: 'Arabic voice',
    languageCodes: ['ar'],
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ar_JO-kareem-medium.tar.bz2',
    archiveSha256: '',
    approxBytes: 80 * 1024 * 1024,
    rootDirName: 'vits-piper-ar_JO-kareem-medium',
    modelFile: ModelFile(relativePath: 'ar_JO-kareem-medium.onnx'),
    tokensFile: ModelFile(relativePath: 'tokens.txt'),
    dataDirName: 'espeak-ng-data',
    sampleRateHint: 22050,
  );

  // ---------------------------------------------------------------------------
  // LLM: Gemma 4 E2B-IT `.litertlm` bundle, consumed directly by
  // flutter_gemma 0.13.6 via ModelType.gemmaIt + ModelFileType.litertlm.
  // Direct-file download (no archive) stored alongside voice packs.
  //
  // Artifact: gemma-4-E2B-it.litertlm (~1.5 GB), the latest LiteRT-LM
  // packaging of the Gemma 4 E2B instruction-tuned checkpoint. The
  // litert-community mirror on HuggingFace is open-license and can be
  // fetched directly without a Kaggle login.
  //
  // URL is parameterised via `--dart-define=AEGIS_GEMMA_URL=...` so an
  // app build can point at a private mirror if HuggingFace is unreachable.
  // ---------------------------------------------------------------------------
  static const String _gemmaUrl = String.fromEnvironment(
    'AEGIS_GEMMA_URL',
    defaultValue:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  );

  static const VoiceModelPack _gemma4E2bIt = VoiceModelPack(
    id: 'llm-gemma-4-e2b-it-litertlm',
    kind: ModelKind.llm,
    displayName: 'Gemma 4 assistant brain',
    languageCodes: _gemmaLanguages,
    archiveUrl: _gemmaUrl,
    archiveSha256: '',
    // Real size on HuggingFace (litert-community mirror): 2,583,085,056 B.
    approxBytes: 2583085056,
    rootDirName: 'gemma-4-e2b-it-litertlm',
    modelFile: ModelFile(relativePath: 'model.litertlm'),
    isArchive: false,
  );

  /// Global LLM list — reused in every region plan.
  static const List<VoiceModelPack> _llmAll = [_gemma4E2bIt];

  /// Global VAD list — reused in every region plan. Silero is tiny and
  /// language-agnostic so a single pack works everywhere.
  static const List<VoiceModelPack> _vadAll = [_sileroVad];

  /// Public getter so UI code can describe the LLM download ahead of time
  /// (size, display name) without depending on a specific region plan.
  static VoiceModelPack get llmPack => _gemma4E2bIt;

  /// Public getter for the VAD pack used by every region plan.
  static VoiceModelPack get vadPack => _sileroVad;

  // ---------------------------------------------------------------------------
  // Country → plan. Transcription is handled by Gemma 4's native audio
  // modality, so no separate STT pack is needed — stt: is always empty.
  // ---------------------------------------------------------------------------

  static const _fallbackTts = _ttsPiperEnUsLessac;

  static final Map<String, RegionModelPlan> _byCountry = {
    // South Asia (English is widely used as a second language — ship the
    // streaming pack so the assistant feels real-time when users speak
    // English; Whisper handles Hindi/Urdu/Bengali utterances).
    'IN': RegionModelPlan(
      countryCode: 'IN',
      tts: const [_ttsPiperHiInPratham, _ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'PK': RegionModelPlan(
      countryCode: 'PK',
      tts: const [_ttsPiperHiInPratham, _ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'BD': RegionModelPlan(
      countryCode: 'BD',
      tts: const [_ttsPiperHiInPratham, _ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'LK': RegionModelPlan(
      countryCode: 'LK',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'NP': RegionModelPlan(
      countryCode: 'NP',
      tts: const [_ttsPiperHiInPratham, _ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),

    // English-first
    'US': RegionModelPlan(
      countryCode: 'US',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'CA': RegionModelPlan(
      countryCode: 'CA',
      tts: const [_ttsPiperEnUsLessac, _ttsPiperFrFrSiwis],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'GB': RegionModelPlan(
      countryCode: 'GB',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'AU': RegionModelPlan(
      countryCode: 'AU',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'NZ': RegionModelPlan(
      countryCode: 'NZ',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'IE': RegionModelPlan(
      countryCode: 'IE',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'SG': RegionModelPlan(
      countryCode: 'SG',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'MY': RegionModelPlan(
      countryCode: 'MY',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'PH': RegionModelPlan(
      countryCode: 'PH',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'ZA': RegionModelPlan(
      countryCode: 'ZA',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'KE': RegionModelPlan(
      countryCode: 'KE',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'NG': RegionModelPlan(
      countryCode: 'NG',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),

    // Europe
    'DE': RegionModelPlan(
      countryCode: 'DE',
      tts: const [_ttsPiperDeDeThorsten],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'AT': RegionModelPlan(
      countryCode: 'AT',
      tts: const [_ttsPiperDeDeThorsten],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'CH': RegionModelPlan(
      countryCode: 'CH',
      tts: const [_ttsPiperDeDeThorsten, _ttsPiperFrFrSiwis],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'FR': RegionModelPlan(
      countryCode: 'FR',
      tts: const [_ttsPiperFrFrSiwis],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'BE': RegionModelPlan(
      countryCode: 'BE',
      tts: const [_ttsPiperFrFrSiwis],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'NL': RegionModelPlan(
      countryCode: 'NL',
      tts: const [_ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'ES': RegionModelPlan(
      countryCode: 'ES',
      tts: const [_ttsPiperEsEsDavefx],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'IT': RegionModelPlan(
      countryCode: 'IT',
      tts: const [_ttsPiperItItRiccardo],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'PT': RegionModelPlan(
      countryCode: 'PT',
      tts: const [_ttsPiperPtBrFaber],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'RU': RegionModelPlan(
      countryCode: 'RU',
      tts: const [_ttsPiperRuRuDenis],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'TR': RegionModelPlan(
      countryCode: 'TR',
      tts: const [_ttsPiperTrTrDfki],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),

    // LATAM
    'MX': RegionModelPlan(
      countryCode: 'MX',
      tts: const [_ttsPiperEsEsDavefx],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'AR': RegionModelPlan(
      countryCode: 'AR',
      tts: const [_ttsPiperEsEsDavefx],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'CO': RegionModelPlan(
      countryCode: 'CO',
      tts: const [_ttsPiperEsEsDavefx],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'CL': RegionModelPlan(
      countryCode: 'CL',
      tts: const [_ttsPiperEsEsDavefx],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'PE': RegionModelPlan(
      countryCode: 'PE',
      tts: const [_ttsPiperEsEsDavefx],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'BR': RegionModelPlan(
      countryCode: 'BR',
      tts: const [_ttsPiperPtBrFaber],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),

    // MENA
    'AE': RegionModelPlan(
      countryCode: 'AE',
      tts: const [_ttsPiperArJoXkadir, _ttsPiperEnGbAlan],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'SA': RegionModelPlan(
      countryCode: 'SA',
      tts: const [_ttsPiperArJoXkadir],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'EG': RegionModelPlan(
      countryCode: 'EG',
      tts: const [_ttsPiperArJoXkadir],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'JO': RegionModelPlan(
      countryCode: 'JO',
      tts: const [_ttsPiperArJoXkadir],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'QA': RegionModelPlan(
      countryCode: 'QA',
      tts: const [_ttsPiperArJoXkadir],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'KW': RegionModelPlan(
      countryCode: 'KW',
      tts: const [_ttsPiperArJoXkadir],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),

    // East Asia (Whisper STT covers zh/ja/ko)
    'CN': RegionModelPlan(
      countryCode: 'CN',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'JP': RegionModelPlan(
      countryCode: 'JP',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'KR': RegionModelPlan(
      countryCode: 'KR',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'ID': RegionModelPlan(
      countryCode: 'ID',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'TH': RegionModelPlan(
      countryCode: 'TH',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
    'VN': RegionModelPlan(
      countryCode: 'VN',
      tts: const [_ttsPiperEnUsLessac],
      stt: const [],
      vad: _vadAll,
      llm: _llmAll,
    ),
  };

  /// Returns the plan for a country, or a safe English + multilingual-STT
  /// fallback when the country is unknown or empty.
  static RegionModelPlan planFor(String countryCode) {
    final code = countryCode.toUpperCase();
    final hit = _byCountry[code];
    if (hit != null) return hit;
    return const RegionModelPlan(
      countryCode: '',
      tts: [_fallbackTts],
      stt: [],
      vad: _vadAll,
      llm: _llmAll,
    );
  }

  /// Find a TTS pack that speaks the given ISO language code, or null.
  /// Used by the language picker to play a sample.
  static VoiceModelPack? ttsForLanguage(String languageCode) {
    final code = languageCode.toLowerCase();
    for (final plan in _byCountry.values) {
      for (final pack in plan.tts) {
        if (pack.languageCodes.contains(code)) return pack;
      }
    }
    return null;
  }

  /// All unique packs in the catalog — useful for admin / debug screens.
  static List<VoiceModelPack> get allPacks {
    final seen = <String, VoiceModelPack>{};
    for (final plan in _byCountry.values) {
      for (final pack in plan.all) {
        seen[pack.id] = pack;
      }
    }
    return seen.values.toList();
  }
}

/// ISO-639 codes the app supports. Used by the VAD pack picker so the
/// language-aware selector doesn't reject the language-agnostic VAD.
const List<String> _allLanguageCodes = [
  'af',
  'am',
  'ar',
  'as',
  'az',
  'ba',
  'be',
  'bg',
  'bn',
  'bo',
  'br',
  'bs',
  'ca',
  'cs',
  'cy',
  'da',
  'de',
  'el',
  'en',
  'es',
  'et',
  'eu',
  'fa',
  'fi',
  'fo',
  'fr',
  'gl',
  'gu',
  'ha',
  'haw',
  'he',
  'hi',
  'hr',
  'ht',
  'hu',
  'hy',
  'id',
  'is',
  'it',
  'ja',
  'jw',
  'ka',
  'kk',
  'km',
  'kn',
  'ko',
  'la',
  'lb',
  'ln',
  'lo',
  'lt',
  'lv',
  'mg',
  'mi',
  'mk',
  'ml',
  'mn',
  'mr',
  'ms',
  'mt',
  'my',
  'ne',
  'nl',
  'nn',
  'no',
  'oc',
  'pa',
  'pl',
  'ps',
  'pt',
  'ro',
  'ru',
  'sa',
  'sd',
  'si',
  'sk',
  'sl',
  'sn',
  'so',
  'sq',
  'sr',
  'su',
  'sv',
  'sw',
  'ta',
  'te',
  'tg',
  'th',
  'tk',
  'tl',
  'tr',
  'tt',
  'uk',
  'ur',
  'uz',
  'vi',
  'yi',
  'yo',
  'zh',
];

/// Languages Gemma 3n handles conversationally. The tokenizer is
/// multilingual but quality is strongest in the following subset.
const List<String> _gemmaLanguages = [
  'ar',
  'bn',
  'de',
  'en',
  'es',
  'fa',
  'fr',
  'gu',
  'hi',
  'id',
  'it',
  'ja',
  'ko',
  'kn',
  'ml',
  'mr',
  'ms',
  'nl',
  'pa',
  'pl',
  'pt',
  'ro',
  'ru',
  'sv',
  'ta',
  'te',
  'th',
  'tr',
  'uk',
  'ur',
  'vi',
  'zh',
];
