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

/// Speech-to-text service backed by Silero VAD + Gemma 4 audio.
///
/// Silero VAD segments the live mic stream into speech clips; each clip is
/// then transcribed by Gemma 4's native audio modality through the injected
/// [_transcribeAudio] callback. This eliminates the ~300 MB Whisper model
/// download while keeping the fast, on-device VAD that segments speech in
/// real time.
///
/// Audio format expected by Gemma: 16 kHz, mono, IEEE float32, ≤ 30 s.
/// The VAD is configured with maxSpeechDuration: 8.0 s so segments never
/// approach that ceiling.
class SttService {
  SttService(this._registry, this._transcribeAudio);

  final ModelRegistry _registry;

  /// Callback that takes a 16 kHz mono IEEE float32 WAV blob and returns
  /// its transcription. Injected at construction time so SttService does
  /// not depend on LlmService directly.
  final Future<String> Function(Uint8List wavBytes) _transcribeAudio;

  so.VoiceActivityDetector? _vad;
  VoiceModelPack? _vadPack;
  bool _bindingsInitialized = false;

  VoiceModelPack? get pack => _vadPack;

  /// Always true — this service emits [SttPartial] events as each
  /// VAD-gated segment is decoded.
  bool get isStreaming => true;

  /// [SttService] no longer requires a separate recognizer pack — Gemma 4
  /// handles transcription. This method is kept for API compatibility so
  /// [AssistantCubit] does not need to change its bootstrap logic; calling
  /// it is a no-op.
  // ignore: avoid_unused_element
  void setPack(VoiceModelPack pack) {}

  /// Mark the VAD pack to use. The actual detector is constructed lazily
  /// on the first streaming call.
  void setVadPack(VoiceModelPack pack) {
    if (_vadPack?.id != pack.id) {
      _disposeVad();
    }
    _vadPack = pack;
  }

  /// True if the VAD pack is set and installed on disk. Gemma availability
  /// is checked separately by [AssistantCubit] via [LlmService].
  Future<bool> isAvailable() async {
    final vad = _vadPack;
    if (vad == null) return false;
    return _registry.isInstalled(vad);
  }

  /// Drive a continuous recognition session from a live audio stream.
  ///
  /// Pushes every incoming audio frame into the Silero VAD. When the VAD
  /// detects an end-of-speech segment, that segment is encoded as a WAV
  /// blob and sent to Gemma 4 for transcription. The cumulative transcript
  /// is emitted as a [SttPartial]. A trailing-silence timer fires the
  /// [SttFinal] so the cubit knows the user finished their turn.
  Stream<SttUpdate> transcribeStream(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
    String? language,
  }) {
    return _streamWithVadAndGemma(
      audio,
      sampleRate: sampleRate,
      language: language,
    );
  }

  /// Record raw speech to a WAV blob (no transcription) and return it
  /// when VAD detects end-of-utterance.
  ///
  /// Used by Triage Mode's voice intake — the responder taps "Voice",
  /// the mic opens, the recording auto-completes after a moment of
  /// silence, and the resulting WAV is attached to the next LLM turn
  /// as evidence. Gemma 4's audio modality consumes the WAV directly,
  /// so we skip the STT round-trip the Ask Mode mic uses. Concatenates
  /// every VAD speech segment into one float32 buffer, then re-encodes
  /// in [_encodeWav]'s mono 16 kHz IEEE-float32 layout.
  ///
  /// Returns null if the stream completes before any speech is
  /// detected. Caller is responsible for cancelling the source stream.
  Future<Uint8List?> recordToWav(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
  }) async {
    final vad = await _ensureVad();
    vad.reset();

    final completer = Completer<Uint8List?>();
    final accumulated = <double>[];
    Timer? endpointTimer;
    var anySpeech = false;

    void emit() {
      endpointTimer?.cancel();
      if (completer.isCompleted) return;
      if (accumulated.isEmpty) {
        completer.complete(null);
        return;
      }
      final samples = Float32List.fromList(accumulated);
      accumulated.clear();
      completer.complete(_encodeWav(samples, sampleRate: sampleRate));
    }

    void scheduleEndpoint() {
      endpointTimer?.cancel();
      endpointTimer = Timer(_endpointSilence, emit);
    }

    void drainSegments() {
      while (!vad.isEmpty()) {
        final segment = vad.front();
        vad.pop();
        if (segment.samples.isEmpty) continue;
        anySpeech = true;
        accumulated.addAll(segment.samples);
        scheduleEndpoint();
      }
    }

    final sub = audio.listen(
      (samples) {
        if (samples.isEmpty || completer.isCompleted) return;
        try {
          vad.acceptWaveform(samples);
          drainSegments();
        } on Object catch (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        }
      },
      onError: (Object error, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(error, st);
      },
      onDone: () {
        try {
          vad.flush();
          drainSegments();
          if (!completer.isCompleted) {
            if (!anySpeech) {
              completer.complete(null);
            } else {
              emit();
            }
          }
        } on Object catch (e, st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        }
      },
      cancelOnError: true,
    );

    try {
      return await completer.future;
    } finally {
      endpointTimer?.cancel();
      await sub.cancel();
    }
  }

  /// Capture raw mic audio into a WAV blob WITHOUT VAD endpointing.
  /// Used for triage audio evidence where the user wants to record up
  /// to [maxDuration] (default 30s, Gemma 4 audio ceiling) of free-form
  /// content — descriptions of a scene, ambient sounds, etc. — and
  /// have the model interpret the whole clip, not just speech
  /// segments.
  ///
  /// Stops when:
  ///   - [maxDuration] elapses → returns accumulated WAV (capped),
  ///   - the source `audio` stream completes (caller cancelled mic),
  ///   - the stream errors,
  ///   - [cancelOn] future completes — lets the caller (typically the
  ///     cubit) trip an early stop when the user re-taps the mic.
  ///
  /// Returns null only when no samples were captured at all.
  Future<Uint8List?> recordRawToWav(
    Stream<Float32List> audio, {
    int sampleRate = 16000,
    Duration maxDuration = const Duration(seconds: 30),
    Future<void>? cancelOn,
  }) async {
    final completer = Completer<Uint8List?>();
    final accumulated = <double>[];
    final maxSamples = sampleRate * maxDuration.inSeconds;
    Timer? cap;

    void emitFinal() {
      cap?.cancel();
      if (completer.isCompleted) return;
      if (accumulated.isEmpty) {
        completer.complete(null);
        return;
      }
      // Cap to maxDuration in case we overshot on the last frame.
      final samples = Float32List.fromList(
        accumulated.length > maxSamples
            ? accumulated.sublist(0, maxSamples)
            : accumulated,
      );
      accumulated.clear();
      completer.complete(_encodeWav(samples, sampleRate: sampleRate));
    }

    cap = Timer(maxDuration, emitFinal);

    final sub = audio.listen(
      (samples) {
        if (samples.isEmpty || completer.isCompleted) return;
        accumulated.addAll(samples);
        if (accumulated.length >= maxSamples) emitFinal();
      },
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      onDone: emitFinal,
      cancelOnError: true,
    );

    final cancelSub = cancelOn?.then((_) {
      if (!completer.isCompleted) emitFinal();
    }).catchError((_) {});

    try {
      return await completer.future;
    } finally {
      cap.cancel();
      await sub.cancel();
      // Awaiting cancelSub keeps the analyzer happy without blocking
      // — it's already resolved by the time we get here in practice.
      await cancelSub;
    }
  }

  /// Release native resources. Safe to call multiple times.
  Future<void> dispose() async {
    _disposeVad();
  }

  // ---- streaming path -------------------------------------------------------

  /// Trailing silence after the last speech segment before we declare the
  /// turn finished.
  static const Duration _endpointSilence = Duration(milliseconds: 1200);

  Stream<SttUpdate> _streamWithVadAndGemma(
    Stream<Float32List> audio, {
    required int sampleRate,
    String? language,
  }) async* {
    final vad = await _ensureVad();
    vad.reset();

    final controller = StreamController<SttUpdate>();
    final accumulated = StringBuffer();
    Timer? endpointTimer;
    var emittedFinal = false;

    void scheduleEndpoint() {
      endpointTimer?.cancel();
      endpointTimer = Timer(_endpointSilence, () {
        if (controller.isClosed) return;
        final text = accumulated.toString().trim();
        if (text.isEmpty) return;
        accumulated.clear();
        emittedFinal = true;
        controller.add(SttFinal(text));
      });
    }

    Future<void> drainSegments() async {
      while (!vad.isEmpty()) {
        final segment = vad.front();
        vad.pop();
        if (segment.samples.isEmpty) continue;

        // Gemma 4 audio supports max 30 s clips. The VAD caps segments at
        // 8 s (maxSpeechDuration) so this assertion should never fire, but
        // we guard defensively.
        final maxSamples = sampleRate * 30;
        final samples =
            segment.samples.length > maxSamples
                ? Float32List.sublistView(segment.samples, 0, maxSamples)
                : segment.samples;

        final wav = _encodeWav(samples, sampleRate: sampleRate);
        final String text;
        try {
          text = await _transcribeAudio(wav);
        } on Object {
          // If transcription fails for a segment, skip it and keep
          // listening rather than killing the whole stream.
          continue;
        }
        if (text.isEmpty) continue;
        if (accumulated.isNotEmpty) accumulated.write(' ');
        accumulated.write(text);
        if (controller.isClosed) return;
        controller.add(SttPartial(accumulated.toString()));
        scheduleEndpoint();
      }
    }

    final sub = audio.listen(
      (samples) {
        if (samples.isEmpty) return;
        try {
          vad.acceptWaveform(samples);
          // drainSegments is async but we call unawaited intentionally:
          // each call operates on a consistent snapshot of the VAD queue
          // while the next audio frames accumulate. Errors are swallowed
          // inside drainSegments so a single bad segment doesn't kill
          // the listener.
          drainSegments().ignore();
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
          await drainSegments();
          if (!emittedFinal) {
            final tail = accumulated.toString().trim();
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

  // ---- VAD factory ----------------------------------------------------------

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
        threshold: 0.5,
        minSilenceDuration: 0.6,
        minSpeechDuration: 0.25,
        maxSpeechDuration: 8.0,
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

  // ---- WAV encoding ---------------------------------------------------------

  /// Encode [samples] (mono float32, -1..+1, [sampleRate] Hz) into a
  /// minimal IEEE-float32 WAV blob. Gemma 4 expects this exact format:
  /// mono, 16 kHz, 32-bit float.
  static Uint8List _encodeWav(Float32List samples, {int sampleRate = 16000}) {
    const int headerBytes = 44;
    final int dataBytes = samples.length * 4;
    final buf = ByteData(headerBytes + dataBytes);

    // RIFF chunk
    buf
      ..setUint8(0, 0x52) // R
      ..setUint8(1, 0x49) // I
      ..setUint8(2, 0x46) // F
      ..setUint8(3, 0x46) // F
      ..setUint32(4, headerBytes - 8 + dataBytes, Endian.little)
      ..setUint8(8, 0x57) // W
      ..setUint8(9, 0x41) // A
      ..setUint8(10, 0x56) // V
      ..setUint8(11, 0x45); // E

    // fmt sub-chunk (IEEE float32 = format 3)
    buf
      ..setUint8(12, 0x66) // f
      ..setUint8(13, 0x6D) // m
      ..setUint8(14, 0x74) // t
      ..setUint8(15, 0x20) //  (space)
      ..setUint32(16, 16, Endian.little) // sub-chunk size
      ..setUint16(20, 3, Endian.little) // IEEE float
      ..setUint16(22, 1, Endian.little) // mono
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 4, Endian.little) // byte rate
      ..setUint16(32, 4, Endian.little) // block align
      ..setUint16(34, 32, Endian.little); // bits per sample

    // data sub-chunk
    buf
      ..setUint8(36, 0x64) // d
      ..setUint8(37, 0x61) // a
      ..setUint8(38, 0x74) // t
      ..setUint8(39, 0x61) // a
      ..setUint32(40, dataBytes, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      buf.setFloat32(headerBytes + i * 4, samples[i], Endian.little);
    }

    return buf.buffer.asUint8List();
  }

  // ---- helpers --------------------------------------------------------------

  void _ensureBindings() {
    if (_bindingsInitialized) return;
    so.initBindings();
    _bindingsInitialized = true;
  }

  void _disposeVad() {
    final vad = _vad;
    _vad = null;
    vad?.free();
  }
}
