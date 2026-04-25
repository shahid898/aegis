import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thrown when the microphone permission is denied or restricted.
class MicrophonePermissionException implements Exception {
  const MicrophonePermissionException(this.status);
  final PermissionStatus status;

  @override
  String toString() => 'MicrophonePermissionException(status: $status)';
}

/// Thin wrapper around `flutter_sound` 9.30 that exposes a mono 16 kHz
/// Float32 microphone stream — the exact shape sherpa-onnx
/// `OnlineRecognizer.acceptWaveform` expects.
///
/// Two recording modes:
///
/// 1. **Batched** — [start] / [stop]. The service accumulates samples in
///    memory and returns the whole utterance from [stop]. Used for
///    Whisper-style non-streaming STT.
/// 2. **Streaming** — [startStream]. Returns a `Stream<Float32List>` that
///    emits PCM frames as flutter_sound captures them. Used for
///    streaming Zipformer STT and any other consumer that needs live
///    audio. Call [stop] (which works in both modes) when done.
///
/// The service is stateful — one active recording at a time, regardless
/// of mode. Mixing modes on the same recording is not supported.
class AudioRecorderService {
  AudioRecorderService();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  static const int sampleRate = 16000;

  bool _opened = false;

  // Underlying flutter_sound sink/stream — created on every recording,
  // disposed on stop/cancel.
  StreamController<List<Float32List>>? _pcmController;
  StreamSubscription<List<Float32List>>? _pcmSub;

  // Batched mode only: caller wants the whole buffer back from stop().
  final List<double> _accumulator = <double>[];
  Completer<Float32List>? _pending;

  // Streaming mode only: every captured frame is forwarded into this
  // controller; the consumer subscribes to its stream.
  StreamController<Float32List>? _frameController;

  /// Open the recorder once at app start (or lazily). Requests mic
  /// permission if not already granted. Safe to call multiple times.
  Future<void> open() async {
    if (_opened) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw MicrophonePermissionException(status);
    }
    await _recorder.openRecorder();
    _opened = true;
  }

  bool get isOpen => _opened;

  bool get isRecording => _recorder.isRecording;

  /// Start capturing microphone audio into an in-memory buffer (batched
  /// mode). Audio is 16 kHz mono Float32 (range -1..+1). Call [stop] to
  /// end the capture and receive the accumulated samples.
  Future<void> start() async {
    if (!_opened) {
      throw StateError('AudioRecorderService.start called before open()');
    }
    if (_isActive) {
      throw StateError(
        'AudioRecorderService.start called while already recording',
      );
    }

    _accumulator.clear();
    final controller = StreamController<List<Float32List>>();
    _pcmController = controller;
    _pending = Completer<Float32List>();

    _pcmSub = controller.stream.listen((frames) {
      if (frames.isEmpty) return;
      // Mono — channel 0 only. (numChannels: 1 is enforced below.)
      final channel = frames.first;
      _accumulator.addAll(channel);
    });

    await _recorder.startRecorder(
      codec: Codec.pcmFloat32,
      toStreamFloat32: controller.sink,
      sampleRate: sampleRate,
      numChannels: 1,
      enableNoiseSuppression: true,
      enableEchoCancellation: true,
    );
  }

  /// Start capturing microphone audio as a live Float32 stream (streaming
  /// mode). Each event is one mono PCM frame at 16 kHz. The stream closes
  /// when [stop] / [cancel] is called or when [dispose] tears the
  /// recorder down.
  ///
  /// The stream is single-subscription. Subscribe before awaiting any
  /// downstream work — events queue if there's no listener yet, but the
  /// recorder will be running and dropping audio on the floor.
  Future<Stream<Float32List>> startStream() async {
    if (!_opened) {
      throw StateError('AudioRecorderService.startStream called before open()');
    }
    if (_isActive) {
      throw StateError(
        'AudioRecorderService.startStream called while already recording',
      );
    }

    final controller = StreamController<List<Float32List>>();
    final frames = StreamController<Float32List>();
    _pcmController = controller;
    _frameController = frames;

    _pcmSub = controller.stream.listen((blocks) {
      if (blocks.isEmpty) return;
      // Mono — channel 0 only.
      final channel = blocks.first;
      if (channel.isEmpty) return;
      if (frames.isClosed) return;
      frames.add(channel);
    });

    await _recorder.startRecorder(
      codec: Codec.pcmFloat32,
      toStreamFloat32: controller.sink,
      sampleRate: sampleRate,
      numChannels: 1,
      enableNoiseSuppression: true,
      enableEchoCancellation: true,
    );

    return frames.stream;
  }

  /// Stop the current recording. In batched mode returns the accumulated
  /// samples; in streaming mode returns an empty buffer (the consumer
  /// already has the frames). In both modes the underlying flutter_sound
  /// recorder is stopped and stream resources are released.
  Future<Float32List> stop() async {
    if (!_isActive) {
      throw StateError(
        'AudioRecorderService.stop called with no active recording',
      );
    }

    try {
      await _recorder.stopRecorder();
    } on Exception {
      // Fall through — we still want to release stream resources so the
      // next recording can start cleanly. Caller sees the empty buffer.
    }

    await _pcmSub?.cancel();
    _pcmSub = null;
    await _pcmController?.close();
    _pcmController = null;

    final frames = _frameController;
    _frameController = null;
    if (frames != null && !frames.isClosed) {
      await frames.close();
    }

    final pending = _pending;
    _pending = null;
    final samples = Float32List.fromList(_accumulator);
    _accumulator.clear();
    pending?.complete(samples);
    return samples;
  }

  /// Abort the current recording without returning samples. Safe to call
  /// when no recording is active.
  Future<void> cancel() async {
    if (!_isActive) return;
    try {
      await _recorder.stopRecorder();
    } on Exception {
      // best-effort
    }
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _pcmController?.close();
    _pcmController = null;

    final frames = _frameController;
    _frameController = null;
    if (frames != null && !frames.isClosed) {
      await frames.close();
    }

    _accumulator.clear();
    _pending = null;
  }

  /// Release all native resources. After this the service cannot be used
  /// until [open] is called again.
  Future<void> dispose() async {
    await cancel();
    if (_opened) {
      await _recorder.closeRecorder();
      _opened = false;
    }
  }

  bool get _isActive => _pending != null || _frameController != null;
}
