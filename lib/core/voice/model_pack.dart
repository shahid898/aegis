/// Data classes describing downloadable voice model packs.
///
/// A "pack" maps to one sherpa-onnx release archive (`.tar.bz2`) that we
/// fetch once, extract, and point the runtime at. Packs are intentionally
/// plain data — persistence is handled by `StorageService` and download
/// orchestration by `ModelPackRepository`.
library;

/// Kind of model shipped inside a pack.
///
/// Voice packs (tts/stt) are extracted `.tar.bz2` bundles from the
/// sherpa-onnx release assets. LLM packs (llm) are single-file downloads
/// of a `.task` bundle consumed directly by flutter_gemma.
enum ModelKind { tts, stt, llm }

/// Single file inside an extracted pack that runtime code references.
///
/// Paths are **relative to the extracted pack root**. Callers join them
/// with the pack's install directory at runtime.
class ModelFile {
  const ModelFile({required this.relativePath, this.description});

  final String relativePath;
  final String? description;
}

/// Descriptor for a single downloadable pack (one archive on disk).
///
/// The descriptor is immutable and safe to embed in a static catalog.
class VoiceModelPack {
  const VoiceModelPack({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.languageCodes,
    required this.archiveUrl,
    required this.archiveSha256,
    required this.approxBytes,
    required this.rootDirName,
    required this.modelFile,
    this.tokensFile,
    this.lexiconFile,
    this.dataDirName,
    this.encoderFile,
    this.decoderFile,
    this.joinerFile,
    this.speakerId = 0,
    this.sampleRateHint,
    this.isArchive = true,
  });

  /// Stable identifier used in storage + DI (e.g. `tts-piper-en_US-lessac`).
  final String id;

  final ModelKind kind;

  /// Human-readable name shown on the download screen.
  final String displayName;

  /// ISO-639 codes this pack covers. Whisper multilingual lists many codes;
  /// Piper packs usually have one.
  final List<String> languageCodes;

  /// Direct URL to the `.tar.bz2` release archive.
  final String archiveUrl;

  /// Hex-encoded SHA-256 of the archive. Empty string disables verification
  /// (only for initial scaffolding — production catalog should fill these in).
  final String archiveSha256;

  /// Approximate on-disk size after extraction, for UI progress and
  /// pre-flight disk-space checks.
  final int approxBytes;

  /// The top-level directory produced by `tar xjf` (e.g.
  /// `vits-piper-en_US-lessac-medium`). Used when joining sub-paths.
  final String rootDirName;

  /// Main `.onnx` model file. Relative to `rootDirName`.
  final ModelFile modelFile;

  /// Token vocabulary (TTS + some STT).
  final ModelFile? tokensFile;

  /// Lexicon (Piper TTS).
  final ModelFile? lexiconFile;

  /// espeak-ng data directory, required by Piper TTS.
  final String? dataDirName;

  // -- Optional extra model files (sherpa-onnx multi-file models) ----------
  final ModelFile? encoderFile;
  final ModelFile? decoderFile;
  final ModelFile? joinerFile;

  /// Default speaker id for multi-speaker TTS models.
  final int speakerId;

  /// Optional sample-rate hint (Piper is typically 22050 Hz).
  final int? sampleRateHint;

  /// When `true` (default) the URL points at a `.tar.bz2` that we extract
  /// into `rootDirName`. When `false` the URL points directly at the
  /// primary artifact (e.g. a flutter_gemma `.task` file) which we copy
  /// verbatim to `rootDirName/modelFile.relativePath`.
  final bool isArchive;
}

/// Plan for a given region: which packs we *want* to install to give the
/// user a good offline experience. The user can skip and continue in
/// degraded mode.
class RegionModelPlan {
  const RegionModelPlan({
    required this.countryCode,
    required this.tts,
    required this.stt,
    this.vad = const [],
    this.llm = const [],
  });

  /// ISO-3166 alpha-2 uppercase, e.g. `IN`, `US`.
  final String countryCode;

  /// Preferred TTS packs for this region (ordered — first is the best
  /// match for the likely primary language).
  final List<VoiceModelPack> tts;

  /// STT packs for this region. Empty since Gemma 4 handles transcription
  /// natively; kept for schema compatibility.
  final List<VoiceModelPack> stt;

  /// Voice Activity Detection packs (typically a single global Silero VAD
  /// pack). VAD chunks the live mic stream into utterances so the
  /// non-streaming Whisper recognizer can decode them turn-by-turn.
  final List<VoiceModelPack> vad;

  /// On-device LLM packs (flutter_gemma `.task` bundles). Typically a
  /// single global pack shared across all regions.
  final List<VoiceModelPack> llm;

  /// All packs flattened in install order (VAD first because it's tiny,
  /// then TTS so the language picker demo plays ASAP, then LLM last because
  /// it is the largest asset).
  List<VoiceModelPack> get all => [...vad, ...tts, ...stt, ...llm];
}
