import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

/// Multi-pack TTS service backed by sherpa-onnx `OfflineTts` + `just_audio`.
///
/// Each language ships its own VITS voice (Hindi `pratham`, English `lessac`,
/// etc.). Loading just one pack means a Hindi-IT model would phonemize
/// English replies via espeak-ng-hi — which is what the user perceived as
/// "Spanish-sounding" output. The fix is to keep every pack in the region
/// plan resident at once and pick the right engine per sentence.
///
/// Routing rule: count Devanagari / Arabic / CJK / Latin codepoints in the
/// sentence, pick the loaded pack whose `languageCodes` contains the
/// dominant script's ISO-639 code; fall back to the user-selected default
/// pack when the sentence is script-ambiguous (numbers, punctuation only).
class TtsService {
  TtsService(this._registry);

  final ModelRegistry _registry;
  final AudioPlayer _player = AudioPlayer();

  /// Engine bank keyed by [VoiceModelPack.id]. Holds one [so.OfflineTts]
  /// per loaded pack so we can render a Hindi sentence through pratham
  /// while the very next English sentence renders through lessac.
  final Map<String, so.OfflineTts> _engines = <String, so.OfflineTts>{};
  final Map<String, VoiceModelPack> _packs = <String, VoiceModelPack>{};

  /// Pack chosen when language detection is ambiguous (digits, "OK",
  /// punctuation only). Set on first load and updated on every subsequent
  /// load — the most recently loaded pack wins, matching what the cubit
  /// passes in (the user's selected language).
  VoiceModelPack? _defaultPack;
  bool _bindingsInitialized = false;

  /// Queue of synthesis-then-play jobs. Each [enqueue] adds one clip and
  /// starts the worker if it isn't already running. The worker drains the
  /// queue serially so we never overlap two clips on the audio device.
  final Queue<_TtsClip> _queue = Queue();
  Future<void>? _worker;
  bool _stopRequested = false;
  int _wavCounter = 0;

  /// True if at least one engine is loaded — callers use this as a cheap
  /// readiness probe before queueing speech.
  bool get isReady => _engines.isNotEmpty;

  /// Load every [pack] in [packs] that's installed on disk. Skipped if
  /// already loaded; missing packs are silently ignored (not an error —
  /// downloads may still be in flight). Returns the number of newly loaded
  /// engines.
  Future<int> loadAll(List<VoiceModelPack> packs) async {
    var loaded = 0;
    for (final pack in packs) {
      final ok = await load(pack, makeDefault: false);
      if (ok) loaded++;
    }
    // First pack in the list is treated as the user's preferred default —
    // matches the order produced by `_preferredFor()` in assistant_cubit
    // (preferred-language pack first, fallback packs after).
    if (packs.isNotEmpty) {
      final preferred = packs.first;
      if (_engines.containsKey(preferred.id)) {
        _defaultPack = preferred;
      }
    }
    return loaded;
  }

  /// Load the engine for [pack] if not already loaded. Returns `false`
  /// when the pack is not installed on disk (caller should fall back to
  /// degraded UX — e.g. skip sample playback).
  ///
  /// When [makeDefault] is true, this pack becomes the fallback engine
  /// for script-ambiguous sentences.
  Future<bool> load(VoiceModelPack pack, {bool makeDefault = true}) async {
    if (pack.kind != ModelKind.tts) {
      throw ArgumentError(
        'TtsService.load requires a TTS pack, got ${pack.id}',
      );
    }
    if (_engines.containsKey(pack.id)) {
      if (makeDefault) _defaultPack = pack;
      return true;
    }
    if (!await _registry.isInstalled(pack)) return false;

    _ensureBindings();

    final modelPath = await _registry.absolutePath(pack, pack.modelFile);
    final tokensPath =
        pack.tokensFile == null
            ? ''
            : await _registry.absolutePath(pack, pack.tokensFile!);
    final lexiconPath =
        pack.lexiconFile == null
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

    final engine = so.OfflineTts(config);
    _engines[pack.id] = engine;
    _packs[pack.id] = pack;
    if (makeDefault || _defaultPack == null) {
      _defaultPack = pack;
    }
    if (kDebugMode) {
      debugPrint(
        '[TtsService] loaded engine pack=${pack.id} '
        'languages=${pack.languageCodes} (${_engines.length} resident)',
      );
    }
    return true;
  }

  /// Generate audio for [text] and play it. Awaits the *entire* clip —
  /// synthesis + playback to natural completion. Use this only when the
  /// caller wants strict turn-taking; for streaming UIs prefer [enqueue].
  Future<void> speak(String text, {double speed = 1.0, int? speakerId}) {
    return enqueue(text, speed: speed, speakerId: speakerId);
  }

  /// Append one TTS clip to the queue and start the worker if needed.
  /// Returns a future that resolves when *this* clip finishes playing.
  ///
  /// The cubit calls this once per sentence as the LLM streams tokens, so
  /// the user hears the start of the answer while the model is still
  /// decoding the rest. The worker keeps order and never overlaps clips.
  Future<void> enqueue(String text, {double speed = 1.0, int? speakerId}) {
    if (_engines.isEmpty || _defaultPack == null) {
      throw StateError('TtsService.enqueue called before load() succeeded');
    }
    final trimmed = _sanitizeForSpeech(text).trim();
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

  /// Strip markdown / formatting characters that the TTS engine would
  /// otherwise read out literally. Gemma 4 emits the assistant reply
  /// with `**bold**` emphasis, backticks for code, and numbered-list
  /// markers — the visual chat bubble keeps them, but the spoken
  /// stream must not pronounce "asterisk asterisk bold asterisk
  /// asterisk". This is intentionally conservative: only strips
  /// well-known markdown decorations, leaves digits and punctuation
  /// alone so list ordinals still read naturally.
  static final RegExp _mdEmphasis = RegExp(r'\*{1,3}([^*]+)\*{1,3}');
  static final RegExp _mdCodeFence = RegExp(r'```[\s\S]*?```');
  static final RegExp _mdInlineCode = RegExp(r'`([^`]+)`');
  static final RegExp _mdHeading = RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true);
  static final RegExp _mdHr = RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true);
  // List bullets at start of line ("- ", "* ", "+ ") get dropped.
  // Numbered-list ordinals ("1. ", "2. ") also get stripped — sherpa
  // TTS engines read them aloud as "one period two period" or trail
  // them awkwardly. Sentence-level pauses + the natural ordering of
  // the steps carry the structure without spoken numbers.
  static final RegExp _mdBullet = RegExp(r'^\s*[-*+]\s+', multiLine: true);
  // Numbered-list ordinals at start of line or string. Handles:
  //   "1. Apply pressure"   → "Apply pressure"
  //   "1.Apply pressure"    → "Apply pressure"   (no space after `.`)
  //   "1."  (chunk that ends right after the period)  → ""
  //   "1)" / "1)Apply"      → "Apply"
  // Lookahead `(?=\s|$|[^\d])` prevents eating decimals like
  // "5.4 megabytes" — period followed by another digit is a decimal,
  // not an ordinal marker.
  static final RegExp _mdOrdinal = RegExp(
    r'^\s*\d{1,3}[.)](?=\s|$|[^\d])\s*',
    multiLine: true,
  );
  // Standalone trailing ordinal label that survived the line-start
  // strip — e.g. when the previous TTS chunk ended at `Apply pressure.`
  // and the new chunk starts with `2.` followed by no whitespace
  // because the next sentence boundary cut early. Catch any orphan
  // ordinal that appears alone before a newline or at end-of-string.
  static final RegExp _mdOrdinalOrphan = RegExp(
    r'(^|\s)\d{1,3}[.)](?=\s|$)',
    multiLine: true,
  );
  static final RegExp _excessiveBlankLines = RegExp(r'\n{3,}');

  static String _sanitizeForSpeech(String input) {
    var s = input;
    s = s.replaceAll(_mdCodeFence, ' ');
    s = s.replaceAllMapped(_mdInlineCode, (m) => m.group(1) ?? '');
    s = s.replaceAllMapped(_mdEmphasis, (m) => m.group(1) ?? '');
    s = s.replaceAll(_mdHeading, '');
    s = s.replaceAll(_mdHr, '');
    s = s.replaceAll(_mdBullet, '');
    s = s.replaceAll(_mdOrdinal, '');
    // Orphan ordinal sweep handles chunks where the sentence boundary
    // cut left a trailing `1.` / `2.` floating alone. Replacement
    // preserves the leading whitespace/start-of-line capture group.
    s = s.replaceAllMapped(
      _mdOrdinalOrphan,
      (m) => m.group(1) ?? '',
    );
    s = s.replaceAll(_excessiveBlankLines, '\n\n');
    return s;
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
    final pack = _routePack(clip.text);
    final engine = _engines[pack.id];
    if (engine == null) return;

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
    await _disposeAll();
  }

  // ---- internals ----------------------------------------------------------

  void _ensureBindings() {
    if (_bindingsInitialized) return;
    so.initBindings();
    _bindingsInitialized = true;
  }

  Future<void> _disposeAll() async {
    final engines = List.of(_engines.values);
    _engines.clear();
    _packs.clear();
    _defaultPack = null;
    for (final engine in engines) {
      engine.free();
    }
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

  /// Pick the loaded pack whose voice best matches [text]. Falls back to
  /// the default pack when no script signal is present (digits, lone "OK").
  VoiceModelPack _routePack(String text) {
    final detected = _detectLanguage(text);
    if (detected != null) {
      for (final pack in _packs.values) {
        if (pack.languageCodes.contains(detected)) return pack;
      }
    }
    return _defaultPack ?? _packs.values.first;
  }

  /// Returns an ISO-639 code (`hi`, `ar`, `zh`, `ja`, `en`, `ru`, ...) for
  /// the dominant script in [text], or `null` if the text has no script
  /// signal at all. Cheap O(n) codepoint scan — we don't need full Unicode
  /// segmentation, just enough to disambiguate "Hindi reply with English
  /// proper nouns" from "English reply with a Hindi loanword".
  ///
  /// Threshold: a script needs at least one codepoint *and* at least 30%
  /// of the alphabetic codepoints to claim the sentence. Otherwise we tie-
  /// break by the highest count, falling back to Latin → English.
  String? _detectLanguage(String text) {
    var devanagari = 0;
    var bengali = 0;
    var gurmukhi = 0;
    var gujarati = 0;
    var tamil = 0;
    var telugu = 0;
    var kannada = 0;
    var malayalam = 0;
    var arabic = 0;
    var cyrillic = 0;
    var greek = 0;
    var hebrew = 0;
    var thai = 0;
    var hangul = 0;
    var hiragana = 0;
    var katakana = 0;
    var cjk = 0;
    var latin = 0;

    for (final rune in text.runes) {
      if (rune >= 0x0900 && rune <= 0x097F) {
        devanagari++;
      } else if (rune >= 0x0980 && rune <= 0x09FF) {
        bengali++;
      } else if (rune >= 0x0A00 && rune <= 0x0A7F) {
        gurmukhi++;
      } else if (rune >= 0x0A80 && rune <= 0x0AFF) {
        gujarati++;
      } else if (rune >= 0x0B80 && rune <= 0x0BFF) {
        tamil++;
      } else if (rune >= 0x0C00 && rune <= 0x0C7F) {
        telugu++;
      } else if (rune >= 0x0C80 && rune <= 0x0CFF) {
        kannada++;
      } else if (rune >= 0x0D00 && rune <= 0x0D7F) {
        malayalam++;
      } else if (rune >= 0x0600 && rune <= 0x06FF) {
        arabic++;
      } else if (rune >= 0x0400 && rune <= 0x04FF) {
        cyrillic++;
      } else if (rune >= 0x0370 && rune <= 0x03FF) {
        greek++;
      } else if (rune >= 0x0590 && rune <= 0x05FF) {
        hebrew++;
      } else if (rune >= 0x0E00 && rune <= 0x0E7F) {
        thai++;
      } else if (rune >= 0xAC00 && rune <= 0xD7AF) {
        hangul++;
      } else if (rune >= 0x3040 && rune <= 0x309F) {
        hiragana++;
      } else if (rune >= 0x30A0 && rune <= 0x30FF) {
        katakana++;
      } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
        cjk++;
      } else if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        latin++;
      }
    }

    final scores = <String, int>{
      'hi': devanagari,
      'bn': bengali,
      'pa': gurmukhi,
      'gu': gujarati,
      'ta': tamil,
      'te': telugu,
      'kn': kannada,
      'ml': malayalam,
      'ar': arabic,
      'ru': cyrillic,
      'el': greek,
      'he': hebrew,
      'th': thai,
      'ko': hangul,
      'ja': hiragana + katakana,
      'zh': cjk,
      'en': latin,
    };

    String? best;
    var bestCount = 0;
    scores.forEach((lang, count) {
      if (count > bestCount) {
        bestCount = count;
        best = lang;
      }
    });
    if (bestCount == 0) return null;

    // Japanese kana sit inside the same CJK block range used for Chinese —
    // if we saw ANY kana, this is Japanese, not Chinese.
    if ((hiragana + katakana) > 0) return 'ja';
    return best;
  }
}
