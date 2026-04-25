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
/// `OfflineRecognizer.acceptWaveform` expects.
///
/// Usage:
/// ```dart
/// final recorder = AudioRecorderService();
/// await recorder.open();
/// final buffer = await recorder.recordUntilStopped(recorder.stop);
/// ```
///
/// The service is stateful — one active recording at a time. `stop()`
/// yields the accumulated samples as a single `Float32List` so callers
/// can feed them straight into Whisper for a non-streaming decode.
class AudioRecorderService {
  AudioRecorderService();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  static const int sampleRate = 16000;

  bool _opened = false;
  StreamController<List<Float32List>>? _pcmController;
  StreamSubscription<List<Float32List>>? _pcmSub;
  final List<double> _accumulator = <double>[];
  Completer<Float32List>? _pending;

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

  /// Start capturing microphone audio into an in-memory buffer. Audio is
  /// 16 kHz mono Float32 (range -1..+1). Call [stop] to end the capture
  /// and receive the accumulated samples.
  Future<void> start() async {
    if (!_opened) {
      throw StateError('AudioRecorderService.start called before open()');
    }
    if (_pending != null) {
      throw StateError('AudioRecorderService.start called while already recording');
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

  /// Stop the current recording and return the captured samples as one
  /// contiguous Float32List at 16 kHz mono.
  Future<Float32List> stop() async {
    final pending = _pending;
    if (pending == null) {
      throw StateError('AudioRecorderService.stop called with no active recording');
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

    final samples = Float32List.fromList(_accumulator);
    _accumulator.clear();
    _pending = null;
    pending.complete(samples);
    return samples;
  }

  /// Abort the current recording without returning samples. Safe to call
  /// when no recording is active.
  Future<void> cancel() async {
    if (_pending == null) return;
    try {
      await _recorder.stopRecorder();
    } on Exception {
      // best-effort
    }
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _pcmController?.close();
    _pcmController = null;
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
}
