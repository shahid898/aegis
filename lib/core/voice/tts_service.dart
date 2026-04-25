import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'model_pack.dart';
import 'model_registry.dart';

class _TtsClip {
  const _TtsClip({required this.text, required this.speed, this.speakerId});
  final String text;
  final double speed;
  final int? speakerId;
}

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

  /// Queue of synthesis-then-play jobs. Each [enqueue] adds one clip and
  /// starts the worker if it isn't already running. The worker drains the
  /// queue serially so we never overlap two clips on the audio device.
  final Queue<_TtsClip> _queue = Queue();
  Future<void>? _worker;
  bool _stopRequested = false;
  int _wavCounter = 0;

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

  /// Generate audio for [text] and play it. Awaits the *entire* clip —
  /// synthesis + playback to natural completion. Use this only when the
  /// caller wants strict turn-taking; for streaming UIs prefer [enqueue].
  Future<void> speak(
    String text, {
    double speed = 1.0,
    int? speakerId,
  }) {
    return enqueue(text, speed: speed, speakerId: speakerId);
  }

  /// Append one TTS clip to the queue and start the worker if needed.
  /// Returns a future that resolves when *this* clip finishes playing.
  ///
  /// The cubit calls this once per sentence as the LLM streams tokens, so
  /// the user hears the start of the answer while the model is still
  /// decoding the rest. The worker keeps order and never overlaps clips.
  Future<void> enqueue(
    String text, {
    double speed = 1.0,
    int? speakerId,
  }) {
    final pack = _loadedPack;
    final engine = _engine;
    if (pack == null || engine == null) {
      throw StateError('TtsService.enqueue called before load() succeeded');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();

    _stopRequested = false;
    final clip = _TtsClip(text: trimmed, speed: speed, speakerId: speakerId);
    final done = Completer<void>();
    _queue.add(clip);
    // Wrap each clip with its own completer so callers can await this clip
    // specifically without coupling to the rest of the queue.
    _clipCompleters[clip] = done;
    _worker ??= _drain();
    return done.future;
  }

  final Map<_TtsClip, Completer<void>> _clipCompleters = {};

  /// Future that resolves when the queue is fully drained (or empty now).
  Future<void> get whenIdle async {
    final worker = _worker;
    if (worker != null) await worker;
  }

  /// Stop playback immediately and discard any pending clips.
  Future<void> stop() async {
    _stopRequested = true;
    _queue.clear();
    // Resolve every pending completer so awaiters of [enqueue] don't hang.
    for (final c in _clipCompleters.values) {
      if (!c.isCompleted) c.complete();
    }
    _clipCompleters.clear();
    await _player.stop();
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        if (_stopRequested) {
          _queue.clear();
          break;
        }
        final clip = _queue.removeFirst();
        final completer = _clipCompleters.remove(clip);
        try {
          await _renderAndPlay(clip);
        } on Object {
          // Swallow per-clip errors so one bad sentence doesn't kill the
          // whole turn — TTS is best-effort, the on-screen text is the
          // source of truth.
        } finally {
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        }
      }
    } finally {
      _worker = null;
    }
  }

  Future<void> _renderAndPlay(_TtsClip clip) async {
    final pack = _loadedPack;
    final engine = _engine;
    if (pack == null || engine == null) return;

    final audio = engine.generate(
      text: clip.text,
      sid: clip.speakerId ?? pack.speakerId,
      speed: clip.speed,
    );

    // Each clip gets its own file so a still-playing clip's wav isn't
    // overwritten by the next one's synthesis. Counter wraps trivially.
    final wavPath = await _nextWavPath(pack);
    final ok = so.writeWave(
      filename: wavPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    if (!ok) return;

    if (_stopRequested) return;
    await _player.setFilePath(wavPath);
    await _player.play();
    // Wait for natural completion (or external stop()) before returning so
    // the next clip queues seamlessly. just_audio surfaces this as
    // ProcessingState.completed on the playerStateStream.
    await _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed || s == ProcessingState.idle,
    );
  }

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

  Future<String> _nextWavPath(VoiceModelPack pack) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/aegis_tts_out');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Rotate through 8 slots so we never overwrite a wav whose playback
    // hasn't finished but also don't grow the cache unboundedly.
    final slot = _wavCounter++ & 7;
    return '${dir.path}/${pack.id}-$slot.wav';
  }
}
