import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'model_pack.dart';
import 'model_registry.dart';

/// Thin wrapper around sherpa-onnx `OfflineTts` with `just_audio` playback.
///
/// The service keeps **one** engine resident at a time — lightweight for a
/// single-voice app. Switching voices calls `free()` on the previous
/// engine before loading the new one.
class TtsService {
  TtsService(this._registry);

  final ModelRegistry _registry;
  final AudioPlayer _player = AudioPlayer();

  so.OfflineTts? _engine;
  VoiceModelPack? _loadedPack;
  bool _bindingsInitialized = false;

  /// Load the engine for [pack] if not already loaded. Returns `false`
  /// when the pack is not installed on disk (caller should fall back to
  /// degraded UX — e.g. skip sample playback).
  Future<bool> load(VoiceModelPack pack) async {
    if (pack.kind != ModelKind.tts) {
      throw ArgumentError('TtsService.load requires a TTS pack, got ${pack.id}');
    }
    if (_loadedPack?.id == pack.id && _engine != null) return true;
    if (!await _registry.isInstalled(pack)) return false;

    _ensureBindings();

    final modelPath = await _registry.absolutePath(pack, pack.modelFile);
    final tokensPath = pack.tokensFile == null
        ? ''
        : await _registry.absolutePath(pack, pack.tokensFile!);
    final lexiconPath = pack.lexiconFile == null
        ? ''
        : await _registry.absolutePath(pack, pack.lexiconFile!);
    final dataDir = await _registry.dataDirPath(pack) ?? '';

    final config = so.OfflineTtsConfig(
      model: so.OfflineTtsModelConfig(
        vits: so.OfflineTtsVitsModelConfig(
          model: modelPath,
          lexicon: lexiconPath,
          tokens: tokensPath,
          dataDir: dataDir,
        ),
        numThreads: 2,
        debug: false,
      ),
    );

    await _disposeEngine();
    _engine = so.OfflineTts(config);
    _loadedPack = pack;
    return true;
  }

  /// Generate audio for [text] and play it. Returns when playback starts.
  /// Call [stop] to interrupt.
  Future<void> speak(
    String text, {
    double speed = 1.0,
    int? speakerId,
  }) async {
    final pack = _loadedPack;
    final engine = _engine;
    if (pack == null || engine == null) {
      throw StateError('TtsService.speak called before load() succeeded');
    }

    final audio = engine.generate(
      text: text,
      sid: speakerId ?? pack.speakerId,
      speed: speed,
    );

    // sherpa returns a Float32List of PCM samples. `writeWave` serializes
    // to a .wav file that just_audio can play without another codec.
    final wavPath = await _tempWavPath(pack);
    final ok = so.writeWave(
      filename: wavPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    if (!ok) {
      throw StateError('writeWave failed for pack ${pack.id}');
    }

    await _player.stop();
    await _player.setFilePath(wavPath);
    await _player.play();
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _player.dispose();
    await _disposeEngine();
  }

  // ---- internals ----------------------------------------------------------

  void _ensureBindings() {
    if (_bindingsInitialized) return;
    so.initBindings();
    _bindingsInitialized = true;
  }

  Future<void> _disposeEngine() async {
    final engine = _engine;
    _engine = null;
    _loadedPack = null;
    engine?.free();
  }

  Future<String> _tempWavPath(VoiceModelPack pack) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/aegis_tts_out');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return '${dir.path}/${pack.id}.wav';
  }
}
