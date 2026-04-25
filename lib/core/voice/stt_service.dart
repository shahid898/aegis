import 'dart:async';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'model_pack.dart';
import 'model_registry.dart';

/// Offline speech-to-text powered by sherpa-onnx Whisper.
///
/// One recognizer is held resident per pack so every transcribe() call
/// reuses the native resources. Whisper is a **non-streaming** model —
/// callers capture a full utterance first (via `AudioRecorderService`)
/// and hand the complete Float32 buffer here.
class SttService {
  SttService(this._registry);

  final ModelRegistry _registry;

  so.OfflineRecognizer? _recognizer;
  VoiceModelPack? _loadedPack;
  bool _bindingsInitialized = false;

  VoiceModelPack? get pack => _loadedPack;

  /// Mark the STT pack to use. Does not load the engine until the first
  /// transcribe() call, to keep onboarding lightweight.
  void setPack(VoiceModelPack pack) {
    if (pack.kind != ModelKind.stt) {
      throw ArgumentError('SttService.setPack requires an STT pack');
    }
    if (_loadedPack?.id != pack.id) {
      _disposeRecognizer();
    }
    _loadedPack = pack;
  }

  /// True if a pack is set and installed on disk.
  Future<bool> isAvailable() async {
    final pack = _loadedPack;
    if (pack == null) return false;
    return _registry.isInstalled(pack);
  }

  /// Transcribe [samples] (mono 16 kHz Float32, range -1..+1) into text.
  /// Returns an empty string if Whisper produced no hypothesis.
  ///
  /// [language] is an optional ISO-639 code to bias Whisper (e.g. 'en',
  /// 'hi'). Leave null for auto-detect.
  Future<String> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
    String? language,
  }) async {
    if (samples.isEmpty) return '';
    final recognizer = await _ensureRecognizer(language: language);

    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      return result.text.trim();
    } finally {
      stream.free();
    }
  }

  /// Release native resources. Safe to call multiple times.
  Future<void> dispose() async {
    _disposeRecognizer();
  }

  // ---- internals ----------------------------------------------------------

  Future<so.OfflineRecognizer> _ensureRecognizer({String? language}) async {
    final pack = _loadedPack;
    if (pack == null) {
      throw StateError('SttService.transcribe called before setPack()');
    }
    if (!await _registry.isInstalled(pack)) {
      throw StateError('STT pack ${pack.id} is not installed');
    }

    final existing = _recognizer;
    if (existing != null) return existing;

    _ensureBindings();

    final encoderRel = pack.encoderFile ?? pack.modelFile;
    final decoderRel = pack.decoderFile;
    if (decoderRel == null) {
      throw StateError('STT pack ${pack.id} is missing a decoder file');
    }
    final tokensRel = pack.tokensFile;
    if (tokensRel == null) {
      throw StateError('STT pack ${pack.id} is missing a tokens file');
    }

    final encoderPath = await _registry.absolutePath(pack, encoderRel);
    final decoderPath = await _registry.absolutePath(pack, decoderRel);
    final tokensPath = await _registry.absolutePath(pack, tokensRel);

    final config = so.OfflineRecognizerConfig(
      model: so.OfflineModelConfig(
        whisper: so.OfflineWhisperModelConfig(
          encoder: encoderPath,
          decoder: decoderPath,
          language: language ?? '',
          task: 'transcribe',
          tailPaddings: -1,
        ),
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
        modelType: 'whisper',
      ),
    );

    final recognizer = so.OfflineRecognizer(config);
    _recognizer = recognizer;
    return recognizer;
  }

  void _ensureBindings() {
    if (_bindingsInitialized) return;
    so.initBindings();
    _bindingsInitialized = true;
  }

  void _disposeRecognizer() {
    final r = _recognizer;
    _recognizer = null;
    r?.free();
  }
}
