import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Lightweight asset-backed cue player for the mic-open / mic-close
/// transitions. We swapped the platform `SystemSound.click` for two
/// short branded clips shipped in `assets/sound/`:
///
///   * `listening_start.mp3`     — played when the mic flips hot.
///   * `listening_end_sound.mp3` — played when capture closes.
///
/// Each cue runs on its own [AudioPlayer] so a rapid start→stop pair
/// (e.g. user taps the mic to end a turn the moment they finished
/// speaking) never interrupts the prior cue. Players are preloaded
/// lazily on the first call so app startup stays cheap.
///
/// All playback is best-effort. Asset decode / playback failures are
/// swallowed (debug-only log) — the assistant pipeline must never
/// stall waiting for a UX cue.
class ListeningCuePlayer {
  ListeningCuePlayer();

  static const String _startAsset = 'assets/sound/listening_start.mp3';
  static const String _endAsset = 'assets/sound/listening_end_sound.mp3';

  final AudioPlayer _start = AudioPlayer();
  final AudioPlayer _end = AudioPlayer();

  bool _startLoaded = false;
  bool _endLoaded = false;
  bool _disposed = false;

  /// Fire-and-forget; await is only useful in tests.
  Future<void> playStart() => _play(_start, _startAsset, isStart: true);

  /// Fire-and-forget; await is only useful in tests.
  Future<void> playStop() => _play(_end, _endAsset, isStart: false);

  Future<void> _play(
    AudioPlayer player,
    String asset, {
    required bool isStart,
  }) async {
    if (_disposed) return;
    try {
      if (isStart ? !_startLoaded : !_endLoaded) {
        await player.setAsset(asset);
        if (isStart) {
          _startLoaded = true;
        } else {
          _endLoaded = true;
        }
      } else {
        await player.seek(Duration.zero);
      }
      await player.play();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[ListeningCuePlayer] $asset playback failed: $e');
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _start.dispose();
    } on Object {
      // best-effort
    }
    try {
      await _end.dispose();
    } on Object {
      // best-effort
    }
  }
}
