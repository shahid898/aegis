import 'dart:async';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'model_pack.dart';
import 'model_registry.dart';

/// Incremental update emitted by [SttService.transcribeStream].
///
/// Two flavours:
///   * [SttPartial] — the recognizer's current best guess for the
///     in-progress utterance. Replace the previous partial in your UI.
///   * [SttFinal] — endpointing fired (silence trailed long enough). The
///     text is committed; further updates belong to the next utterance.
///
/// `text` is normalized — leading/trailing whitespace stripped — but
/// otherwise identical to what the recognizer reports.
sealed class SttUpdate {
  const SttUpdate(this.text);
  final String text;
}

final class SttPartial extends SttUpdate {
  const SttPartial(super.text);
}

final class SttFinal extends SttUpdate {
  const SttFinal(super.text);
}

/// Speech-to-text service with two backends:
///
/// - **Streaming Zipformer transducer** (preferred for English) — emits
///   live partial hypotheses and detects sentence endpoints from
///   trailing silence. Use [transcribeStream] to drive a continuous
///   pipeline.
/// - **Whisper offline** (multilingual fallback) — non-streaming. Use
///   [transcribe] for batched audio, or [transcribeStream] to get a
///   single [SttFinal] when the input stream closes.
///
/// One recognizer is held resident per pack so every call reuses the
/// native resources.
class SttService {
  SttService(this._registry);

  final ModelRegistry _registry;

  so.OfflineRecognizer? _offline;
  so.OnlineRecognizer? _online;
  VoiceModelPack? _loadedPack;
  bool _bindingsInitialized = false;

  VoiceModelPack? get pack => _loadedPack;

  /// True when the bound pack uses a streaming recognizer (live partials
  /// + endpointing). Callers can branch on this for UX hints.
  bool get isStreaming => _loadedPack?.joinerFile != null;

  /// Mark the STT pack to use. Does not load the engine until the first
  /// transcribe() call, to keep onboarding lightweight.
  void setPack(VoiceModelPack pack) {
    if (pack.kind != ModelKind.stt) {
      throw ArgumentError('SttService.setPack requires an STT pack');
    }
    if (_loadedPack?.id != pack.id) {
      _disposeRecognizers();
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
  /// Returns an empty string if the recognizer produced no hypothesis.
  ///
  /// Used by the (rare) path that needs a single batched decode — the
  /// continuous pipeline uses [transcribeStream] instead.
  Future<String> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
    String? language,
  }) async {
    if (samples.isEmpty) return '';
    final pack = _requireInstalledPack();

    if (pack.joinerFile != null) {
      // Streaming recognizer used as a one-shot — accept the whole buffer,
      // drain decode, read the final hypothesis.
      final recognizer = await _ensureOnlineRecognizer();
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
        stream.inputFinished();
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
        return recognizer.getResult(stream).text.trim();
      } finally {
        stream.free();
      }
    }

    final recognizer = await _ensureOfflineRecognizer(language: language);
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  /// Drive a continuous recognition session from a live audio stream.
  ///
  /// Streaming Zipformer path: emits [SttPartial] as the hypothesis
  /// changes, and [SttFinal] each time the recognizer reports an
  /// endpoint (trailing silence past the configured threshold). The
  /// recognizer state is reset between utterances so a single mic
  /// session can produce several finals.
  ///
  /// Whisper path: buffers the entire input stream, then emits a single
  /// [SttFinal] when the input closes. No partials are emitted.
  ///
  /// The returned stream closes once [audio] closes and the trailing
  /// hypothesis has been emitted.
  Stream<SttUpdate> transcribeStream(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
    String? language,
  }) async* {
    final pack = _requireInstalledPack();

    if (pack.joinerFile != null) {
      yield* _transcribeStreamingTransducer(audio, sampleRate: sampleRate);
    } else {
      yield* _transcribeStreamingWhisper(
        audio,
        sampleRate: sampleRate,
        language: language,
      );
    }
  }

  /// Release native resources. Safe to call multiple times.
  Future<void> dispose() async {
    _disposeRecognizers();
  }

  // ---- streaming paths ----------------------------------------------------

  Stream<SttUpdate> _transcribeStreamingTransducer(
    Stream<Float32List> audio, {
    required int sampleRate,
  }) async* {
    final recognizer = await _ensureOnlineRecognizer();
    final stream = recognizer.createStream();

    final controller = StreamController<SttUpdate>();
    var lastEmittedPartial = '';

    void drainAndEmit() {
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final current = recognizer.getResult(stream).text.trim();
      final reachedEndpoint = recognizer.isEndpoint(stream);
      if (reachedEndpoint) {
        if (current.isNotEmpty) {
          controller.add(SttFinal(current));
        }
        recognizer.reset(stream);
        lastEmittedPartial = '';
        return;
      }
      if (current != lastEmittedPartial) {
        lastEmittedPartial = current;
        if (current.isNotEmpty) {
          controller.add(SttPartial(current));
        }
      }
    }

    final sub = audio.listen(
      (samples) {
        if (samples.isEmpty) return;
        stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
        drainAndEmit();
      },
      onError: (Object error, StackTrace st) {
        controller.addError(error, st);
      },
      onDone: () async {
        // Flush trailing context so the last few hundred ms decode.
        try {
          stream.inputFinished();
          while (recognizer.isReady(stream)) {
            recognizer.decode(stream);
          }
          final tail = recognizer.getResult(stream).text.trim();
          if (tail.isNotEmpty && tail != lastEmittedPartial) {
            controller.add(SttFinal(tail));
          }
        } on Object catch (e, st) {
          controller.addError(e, st);
        } finally {
          stream.free();
          await controller.close();
        }
      },
      cancelOnError: true,
    );

    try {
      yield* controller.stream;
    } finally {
      await sub.cancel();
      if (!controller.isClosed) {
        // Defensive: if the consumer cancels mid-utterance, free the
        // native stream so we don't leak.
        stream.free();
        await controller.close();
      }
    }
  }

  Stream<SttUpdate> _transcribeStreamingWhisper(
    Stream<Float32List> audio, {
    required int sampleRate,
    String? language,
  }) async* {
    // Whisper is non-streaming: buffer everything and decode once at end.
    final accumulator = <double>[];
    await for (final chunk in audio) {
      if (chunk.isEmpty) continue;
      accumulator.addAll(chunk);
    }
    if (accumulator.isEmpty) return;

    final samples = Float32List.fromList(accumulator);
    final recognizer = await _ensureOfflineRecognizer(language: language);
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text.trim();
      if (text.isNotEmpty) {
        yield SttFinal(text);
      }
    } finally {
      stream.free();
    }
  }

  // ---- recognizer factories ----------------------------------------------

  Future<so.OnlineRecognizer> _ensureOnlineRecognizer() async {
    final existing = _online;
    if (existing != null) return existing;

    final pack = _requireInstalledPack();
    final encoderRel = pack.encoderFile ?? pack.modelFile;
    final decoderRel = pack.decoderFile;
    final joinerRel = pack.joinerFile;
    final tokensRel = pack.tokensFile;
    if (decoderRel == null || joinerRel == null || tokensRel == null) {
      throw StateError(
        'STT pack ${pack.id} is missing encoder/decoder/joiner/tokens for '
        'streaming transducer',
      );
    }

    _ensureBindings();

    final encoderPath = await _registry.absolutePath(pack, encoderRel);
    final decoderPath = await _registry.absolutePath(pack, decoderRel);
    final joinerPath = await _registry.absolutePath(pack, joinerRel);
    final tokensPath = await _registry.absolutePath(pack, tokensRel);

    final config = so.OnlineRecognizerConfig(
      model: so.OnlineModelConfig(
        transducer: so.OnlineTransducerModelConfig(
          encoder: encoderPath,
          decoder: decoderPath,
          joiner: joinerPath,
        ),
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
        modelType: 'zipformer2',
      ),
      // Endpointing: tuned to feel snappy but not cut off mid-sentence.
      // rule1 = 2.4 s of silence before any speech (long pre-roll).
      // rule2 = 1.2 s trailing silence after speech — fires the endpoint
      //   that lets us hand the utterance to the LLM.
      // rule3 = 20 s utterance hard-stop guard.
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.0,
      rule3MinUtteranceLength: 20,
    );

    final recognizer = so.OnlineRecognizer(config);
    _online = recognizer;
    return recognizer;
  }

  Future<so.OfflineRecognizer> _ensureOfflineRecognizer({
    String? language,
  }) async {
    final existing = _offline;
    if (existing != null) return existing;

    final pack = _requireInstalledPack();
    final encoderRel = pack.encoderFile ?? pack.modelFile;
    final decoderRel = pack.decoderFile;
    final tokensRel = pack.tokensFile;
    if (decoderRel == null) {
      throw StateError('STT pack ${pack.id} is missing a decoder file');
    }
    if (tokensRel == null) {
      throw StateError('STT pack ${pack.id} is missing a tokens file');
    }

    _ensureBindings();

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
    _offline = recognizer;
    return recognizer;
  }

  // ---- helpers ------------------------------------------------------------

  VoiceModelPack _requireInstalledPack() {
    final pack = _loadedPack;
    if (pack == null) {
      throw StateError('SttService used before setPack()');
    }
    return pack;
  }

  void _ensureBindings() {
    if (_bindingsInitialized) return;
    so.initBindings();
    _bindingsInitialized = true;
  }

  void _disposeRecognizers() {
    final offline = _offline;
    _offline = null;
    offline?.free();
    final online = _online;
    _online = null;
    online?.free();
  }
}
