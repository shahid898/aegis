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

/// Speech-to-text service backed by Whisper-tiny + Silero VAD.
///
/// Whisper alone is non-streaming (it needs a complete utterance to
/// decode), so we put a Silero voice activity detector in front of the
/// live mic stream. The VAD chunks audio into speech segments as the user
/// talks; each segment is decoded by Whisper and emitted as a
/// [SttPartial]. A short trailing silence after the last segment fires
/// the [SttFinal], which the cubit treats as the turn boundary.
///
/// Native resources are held resident across calls. The recognizer is
/// rebuilt only when the bound pack changes; the VAD is rebuilt only
/// when a different VAD pack is bound (rare — there's only one in the
/// catalog today).
class SttService {
  SttService(this._registry);

  final ModelRegistry _registry;

  so.OfflineRecognizer? _offline;
  so.VoiceActivityDetector? _vad;
  VoiceModelPack? _loadedPack;
  VoiceModelPack? _vadPack;
  bool _bindingsInitialized = false;

  VoiceModelPack? get pack => _loadedPack;

  /// VAD-gated Whisper streams partials as each segment decodes, but the
  /// underlying recognizer is non-streaming. Surfaced for UX parity with
  /// the previous streaming-Zipformer path; kept `true` because the
  /// pipeline still emits `SttPartial`s during a turn.
  bool get isStreaming => true;

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

  /// Mark the VAD pack to use. The actual detector is constructed
  /// lazily on the first streaming call.
  void setVadPack(VoiceModelPack pack) {
    if (_vadPack?.id != pack.id) {
      _disposeVad();
    }
    _vadPack = pack;
  }

  /// True if a pack is set and installed on disk. The recognizer pack is
  /// required; the VAD pack is required for streaming but not for one-shot
  /// transcribe() calls, so it's only checked when present.
  Future<bool> isAvailable() async {
    final pack = _loadedPack;
    if (pack == null) return false;
    if (!await _registry.isInstalled(pack)) return false;
    final vad = _vadPack;
    if (vad != null && !await _registry.isInstalled(vad)) return false;
    return true;
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
    _requireInstalledPack();

    final recognizer = await _ensureOfflineRecognizer(language: language);
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      return _prettify(recognizer.getResult(stream).text.trim());
    } finally {
      stream.free();
    }
  }

  /// Drive a continuous recognition session from a live audio stream.
  ///
  /// Pushes every incoming audio frame into the Silero VAD. When the VAD
  /// detects an end-of-speech segment, that segment is decoded by Whisper
  /// and the cumulative transcript is emitted as a [SttPartial]. A
  /// trailing-silence timer ([_endpointSilence]) fires the [SttFinal] so
  /// the cubit knows the user finished their turn.
  ///
  /// The returned stream closes once [audio] closes and the trailing
  /// hypothesis has been emitted.
  Stream<SttUpdate> transcribeStream(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
    String? language,
  }) {
    return _transcribeWhisperWithVad(
      audio,
      sampleRate: sampleRate,
      language: language,
    );
  }

  /// Release native resources. Safe to call multiple times.
  Future<void> dispose() async {
    _disposeRecognizer();
    _disposeVad();
  }

  // ---- streaming path -----------------------------------------------------

  /// Trailing silence after the last detected speech segment before we
  /// declare the turn finished. Indian-English / non-native speakers
  /// pause ~0.6–1.0 s mid-thought; 1.2 s feels conversational without
  /// dragging the assistant's response.
  static const Duration _endpointSilence = Duration(milliseconds: 1200);

  Stream<SttUpdate> _transcribeWhisperWithVad(
    Stream<Float32List> audio, {
    required int sampleRate,
    String? language,
  }) async* {
    _requireInstalledPack();
    final vad = await _ensureVad();
    vad.reset();
    final recognizer = await _ensureOfflineRecognizer(language: language);

    final controller = StreamController<SttUpdate>();
    final accumulated = StringBuffer();
    Timer? endpointTimer;
    var emittedFinal = false;

    void scheduleEndpoint() {
      endpointTimer?.cancel();
      endpointTimer = Timer(_endpointSilence, () {
        if (controller.isClosed) return;
        final text = _prettify(accumulated.toString().trim());
        if (text.isEmpty) return;
        accumulated.clear();
        emittedFinal = true;
        controller.add(SttFinal(text));
      });
    }

    void drainSegments() {
      while (!vad.isEmpty()) {
        final segment = vad.front();
        vad.pop();
        if (segment.samples.isEmpty) continue;
        final stream = recognizer.createStream();
        String text;
        try {
          stream.acceptWaveform(
            samples: segment.samples,
            sampleRate: sampleRate,
          );
          recognizer.decode(stream);
          text = recognizer.getResult(stream).text.trim();
        } finally {
          stream.free();
        }
        if (text.isEmpty) continue;
        if (accumulated.isNotEmpty) accumulated.write(' ');
        accumulated.write(text);
        if (controller.isClosed) return;
        controller.add(SttPartial(_prettify(accumulated.toString())));
        scheduleEndpoint();
      }
    }

    final sub = audio.listen(
      (samples) {
        if (samples.isEmpty) return;
        try {
          vad.acceptWaveform(samples);
          drainSegments();
        } on Object catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      },
      onError: (Object error, StackTrace st) {
        if (!controller.isClosed) controller.addError(error, st);
      },
      onDone: () async {
        try {
          endpointTimer?.cancel();
          vad.flush();
          drainSegments();
          if (!emittedFinal) {
            final tail = _prettify(accumulated.toString().trim());
            if (tail.isNotEmpty) {
              accumulated.clear();
              if (!controller.isClosed) controller.add(SttFinal(tail));
            }
          }
        } on Object catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        } finally {
          if (!controller.isClosed) await controller.close();
        }
      },
      cancelOnError: true,
    );

    try {
      yield* controller.stream;
    } finally {
      endpointTimer?.cancel();
      await sub.cancel();
      if (!controller.isClosed) await controller.close();
    }
  }

  // ---- recognizer factories ----------------------------------------------

  Future<so.VoiceActivityDetector> _ensureVad() async {
    final existing = _vad;
    if (existing != null) return existing;

    final pack = _vadPack;
    if (pack == null) {
      throw StateError(
        'SttService used before setVadPack(); VAD pack is required for '
        'streaming transcription',
      );
    }
    if (!await _registry.isInstalled(pack)) {
      throw StateError('VAD pack ${pack.id} is not installed');
    }

    _ensureBindings();

    final modelPath = await _registry.absolutePath(pack, pack.modelFile);

    final config = so.VadModelConfig(
      sileroVad: so.SileroVadModelConfig(
        model: modelPath,
        // Detection threshold: 0.5 is the Silero default; below this and
        // the model treats the frame as silence. Lower = more permissive
        // (catches softer speech but also more false positives from
        // background noise).
        threshold: 0.5,
        // Within-segment silence before VAD declares the segment done.
        // Short enough to feel snappy mid-utterance — Whisper decodes the
        // first segment while the user keeps talking.
        minSilenceDuration: 0.6,
        // Reject very short noise blips (< 250 ms) so a cough doesn't
        // produce an empty segment.
        minSpeechDuration: 0.25,
        // Hard cap per segment — long monologues get split rather than
        // overflowing Whisper's 30 s window.
        maxSpeechDuration: 8.0,
        // Silero v5 native window size.
        windowSize: 512,
      ),
      sampleRate: 16000,
      numThreads: 1,
      provider: 'cpu',
      debug: false,
    );

    final detector = so.VoiceActivityDetector(
      config: config,
      bufferSizeInSeconds: 30,
    );
    _vad = detector;
    return detector;
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

  /// Whisper produces cased text, so this is a no-op for the current
  /// catalog. Kept around defensively in case we add a different
  /// recognizer down the line — if a model emits >80% uppercase letters
  /// (e.g. a GigaSpeech-trained Zipformer), we lowercase + sentence-case
  /// it so the transcript bubble doesn't look like the assistant is
  /// shouting at the user.
  String _prettify(String text) {
    if (text.isEmpty) return text;
    if (!_isMostlyUpperCase(text)) return text;

    final lower = text.toLowerCase();
    final out = StringBuffer();
    var capitalizeNext = true;
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      final isLetter = _asciiLowerLetter(ch);
      if (capitalizeNext && isLetter) {
        out.write(ch.toUpperCase());
        capitalizeNext = false;
      } else {
        out.write(ch);
      }
      if (ch == '.' || ch == '!' || ch == '?' || ch == '\n') {
        capitalizeNext = true;
      }
    }
    return out.toString();
  }

  bool _isMostlyUpperCase(String text) {
    var letters = 0;
    var upper = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final isLower = c >= 0x61 && c <= 0x7A;
      final isUpper = c >= 0x41 && c <= 0x5A;
      if (isLower || isUpper) letters++;
      if (isUpper) upper++;
    }
    if (letters == 0) return false;
    return upper / letters > 0.8;
  }

  bool _asciiLowerLetter(String ch) {
    if (ch.length != 1) return false;
    final c = ch.codeUnitAt(0);
    return c >= 0x61 && c <= 0x7A;
  }

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

  void _disposeRecognizer() {
    final offline = _offline;
    _offline = null;
    offline?.free();
  }

  void _disposeVad() {
    final vad = _vad;
    _vad = null;
    vad?.free();
  }
}
