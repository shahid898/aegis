import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Inline player for survivor / responder voice notes attached to a
/// triage turn. WAV bytes get spilled to a content-hashed temp file
/// (avoids just_audio's HTTP-proxy + cleartext blocking), then loaded
/// via `setFilePath`. Same bytes across rebuilds reuse the same path.
class AegisAudioChip extends StatefulWidget {
  const AegisAudioChip({super.key, required this.wavBytes});

  final Uint8List wavBytes;

  @override
  State<AegisAudioChip> createState() => _AegisAudioChipState();
}

class _AegisAudioChipState extends State<AegisAudioChip> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  bool _ready = false;
  bool _playing = false;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _bind();
  }

  Future<void> _bind() async {
    try {
      final dir = await getTemporaryDirectory();
      final hash = md5.convert(widget.wavBytes).toString().substring(0, 16);
      final file = File('${dir.path}/aegis-evidence-$hash.wav');
      if (!await file.exists()) {
        await file.writeAsBytes(widget.wavBytes, flush: true);
      }
      final loaded = await _player.setFilePath(file.path);
      if (!mounted) return;
      setState(() {
        _duration = loaded ?? Duration.zero;
        _ready = true;
      });
      _stateSub = _player.playerStateStream.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s.playing &&
            s.processingState != ProcessingState.completed);
        if (s.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
    } on Object catch (e) {
      debugPrint('[Aegis][AudioEvidence] bind failed: $e');
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.seek(Duration.zero);
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = (widget.wavBytes.length / 1024).toStringAsFixed(0);
    final durationLabel = _duration > Duration.zero
        ? _fmtDuration(_duration)
        : '$size KB';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: _ready ? _toggle : null,
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.graphic_eq, size: 16, color: Colors.indigo),
          const SizedBox(width: 6),
          Text(
            'Voice note · $durationLabel',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
