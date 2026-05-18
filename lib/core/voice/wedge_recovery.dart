import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Snapshot of the in-flight triage intake captured by the cubit at
/// the moment the engine wedged, persisted to disk so the auto-
/// relaunched process can replay the same submission without losing
/// the user's photo / audio / typed text. Stored as a JSON sidecar +
/// raw binary attachment files inside the recovery directory.
@immutable
class PendingWedgeIntake {
  const PendingWedgeIntake({
    required this.transcript,
    required this.gpsContext,
    this.imageJpegPath,
    this.audioWavPath,
  });

  final String transcript;
  final String? gpsContext;
  final String? imageJpegPath;
  final String? audioWavPath;

  Map<String, Object?> toJson() => <String, Object?>{
        'transcript': transcript,
        'gpsContext': gpsContext,
        'imageJpegPath': imageJpegPath,
        'audioWavPath': audioWavPath,
      };

  factory PendingWedgeIntake.fromJson(Map<String, Object?> json) =>
      PendingWedgeIntake(
        transcript: (json['transcript'] as String?) ?? '',
        gpsContext: json['gpsContext'] as String?,
        imageJpegPath: json['imageJpegPath'] as String?,
        audioWavPath: json['audioWavPath'] as String?,
      );
}

/// Persists pending triage intake to disk before the process is killed
/// for OpenCL recovery, and reads it back on next launch. The relaunch
/// path uses [tryConsumePending] to detect a wedge-restart and replay
/// the user's triage without them having to redo capture.
class WedgeRecoveryStore {
  WedgeRecoveryStore({Directory? overrideRoot}) : _overrideRoot = overrideRoot;

  static const String _sidecarFileName = 'pending_intake.json';
  static const String _imageFileName = 'pending_image.jpg';
  static const String _audioFileName = 'pending_audio.wav';

  final Directory? _overrideRoot;

  Future<Directory> _root() async {
    if (_overrideRoot != null) return _overrideRoot;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/aegis-wedge-recovery');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Save the pending intake under the recovery directory. Returns the
  /// sidecar path on success. Caller should invoke this BEFORE invoking
  /// the platform-channel restart so the new process can pick it up.
  Future<PendingWedgeIntake> save({
    required String transcript,
    required String? gpsContext,
    Uint8List? imageJpeg,
    Uint8List? audioWav,
  }) async {
    final root = await _root();
    String? imagePath;
    String? audioPath;
    if (imageJpeg != null && imageJpeg.isNotEmpty) {
      imagePath = '${root.path}/$_imageFileName';
      await File(imagePath).writeAsBytes(imageJpeg, flush: true);
    }
    if (audioWav != null && audioWav.isNotEmpty) {
      audioPath = '${root.path}/$_audioFileName';
      await File(audioPath).writeAsBytes(audioWav, flush: true);
    }
    final intake = PendingWedgeIntake(
      transcript: transcript,
      gpsContext: gpsContext,
      imageJpegPath: imagePath,
      audioWavPath: audioPath,
    );
    final sidecar = File('${root.path}/$_sidecarFileName');
    await sidecar.writeAsString(jsonEncode(intake.toJson()), flush: true);
    return intake;
  }

  /// Read + DELETE any pending intake left over from a prior wedge
  /// restart. One-shot — the data is removed regardless of whether
  /// the caller actually replays it, so a runaway recovery loop can't
  /// keep replaying a doomed triage.
  Future<({PendingWedgeIntake intake, Uint8List? image, Uint8List? audio})?>
      tryConsumePending() async {
    final root = await _root();
    final sidecar = File('${root.path}/$_sidecarFileName');
    if (!sidecar.existsSync()) return null;
    try {
      final raw = await sidecar.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        await clear();
        return null;
      }
      final intake = PendingWedgeIntake.fromJson(decoded);
      Uint8List? image;
      Uint8List? audio;
      final imagePath = intake.imageJpegPath;
      if (imagePath != null) {
        final f = File(imagePath);
        if (f.existsSync()) image = await f.readAsBytes();
      }
      final audioPath = intake.audioWavPath;
      if (audioPath != null) {
        final f = File(audioPath);
        if (f.existsSync()) audio = await f.readAsBytes();
      }
      await clear();
      return (intake: intake, image: image, audio: audio);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[WedgeRecovery] consume failed: $e');
      }
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    final root = await _root();
    for (final name in const <String>[
      _sidecarFileName,
      _imageFileName,
      _audioFileName,
    ]) {
      final f = File('${root.path}/$name');
      if (f.existsSync()) {
        try {
          await f.delete();
        } on Object {
          // best-effort
        }
      }
    }
  }
}

/// Thin wrapper around the `com.resq.aegis/restart` MethodChannel
/// implemented by [RestartHelper.kt] in the Android host. Kills the
/// current Android process and relaunches MainActivity ~200ms later
/// via AlarmManager. Use to recover the OpenCL context after a Mali
/// GPU wedge.
class WedgeRestarter {
  WedgeRestarter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.resq.aegis/restart');

  final MethodChannel _channel;

  /// Fire the kill-and-relaunch flow. Caller MUST have persisted any
  /// in-flight state BEFORE this returns — once the alarm fires the
  /// current process is gone.
  Future<void> restartNow({String reason = 'engine-wedged'}) async {
    if (kDebugMode) {
      debugPrint('[WedgeRestarter] requesting process restart reason=$reason');
    }
    try {
      await _channel.invokeMethod<void>('restartApp', <String, Object?>{
        'reason': reason,
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[WedgeRestarter] restart invoke failed: $e');
      }
      rethrow;
    }
  }
}
