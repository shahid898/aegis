import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:genui/genui.dart' show Catalog;

import '../skills/skills_registry.dart';
import 'model_pack.dart';
import 'model_registry.dart';
import 'triage_input.dart';

/// Reserved Gemma / LiteRT-LM tokens that should never appear in a final
/// user-facing reply. We've observed at least `<unused3>` and `<mask>`
/// leak through when the LiteRT-LM chat template doesn't line up perfectly
/// with what the weights were trained against — the model lands in regions
/// of the embedding space where these reserved IDs have non-trivial
/// probability mass and the sampler eventually picks them. The list below
/// covers every special token Gemma's tokenizer reserves plus the chat-
/// template markers LiteRT-LM injects (so a half-emitted `<|turn>` or
/// `<channel|>` gets cleaned up too). The pattern is restricted to
/// `<word>` / `<|word|>` shapes so it won't clobber legitimate text like
/// `<3` or arrow glyphs.
final RegExp _reservedToken = RegExp(
  r'<\|?(?:'
  r'unused\d+|mask|pad|eos|bos|unk|sep|cls'
  r'|start_of_turn|end_of_turn|start_of_image|end_of_image'
  r'|extra_id_\d+'
  r'|turn|think|channel|im_start|im_end'
  r')\|?>',
);

/// Gemma 4 IT chain-of-thought delimiters. With `enableThinking: true` the
/// model wraps its scratchpad in these markers and emits the real reply
/// after `<channel|>`. We keep the reasoning *internal* — the streaming
/// filter drops everything between the markers so the cubit only ever sees
/// the final answer. (The same filter doubles as a safety net when
/// `enableThinking` is later flipped off, since flutter_gemma's own chat
/// layer warns the flag "is not reliable for all model bundles".)
const String _thinkStart = '<|channel>thought\n';
const String _thinkEnd = '<channel|>';
final RegExp _thinkBlockRegex = RegExp(
  r'<\|channel>thought\n.*?<channel\|>',
  dotAll: true,
);

final RegExp _leadingQuote = RegExp(
  r'''^(?:"|“|'|`)+\s*|\s*(?:"|”|'|`)+$''',
);

// Gemma occasionally returns a capability/refusal sentence for audio turns
// (for example "I cannot transcribe the audio... I am a text-based AI").
// That text is not a transcription and should never be forwarded as user
// input to the assistant chat turn.
final RegExp _asrRefusalPattern = RegExp(
  r'''\b(?:
(?:can(?:not|'t)|unable to)\s+transcrib\w*.*\baudio\b
|text-?based\s+ai
|do not have (?:the )?capabilit\w+ to process audio
|cannot process audio
)\b''',
  caseSensitive: false,
  dotAll: true,
);

/// ISO-639 → human-readable name. Injected into the system prompt so we
/// can pin Gemma's reply language without hoping the model auto-detects
/// from a short utterance (it routinely doesn't on noisy audio). Only the
/// languages we actually ship a TTS voice for are listed — anything else
/// falls back to the generic "match the user" rule.
const Map<String, String> _languageNames = {
  'en': 'English',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'gu': 'Gujarati',
  'pa': 'Punjabi',
  'ta': 'Tamil',
  'te': 'Telugu',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'mr': 'Marathi',
  'ur': 'Urdu',
  'ar': 'Arabic',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'ru': 'Russian',
  'tr': 'Turkish',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'id': 'Indonesian',
  'vi': 'Vietnamese',
  'th': 'Thai',
};

/// Emergency-assistant system prompt shared by every session. Kept short
/// because Gemma 3n context is precious and emergency answers must stay
/// terse and actionable. The `{language}` placeholder is filled at chat-
/// build time with the user's selected language so the model never drifts
/// from the voice the TTS bank is set up to speak.
const String _aegisSystemPromptTemplate = '''
You are Aegis, an offline emergency assistant. The user may be injured, in
danger, or trying to help someone who is. Follow these rules on every turn:

1. If the situation is life-threatening, tell the user to call emergency
   services immediately.
2. Answer in plain language, one step at a time, short sentences. Prefer
   numbered steps when giving first-aid instructions.
3. Never invent locations, phone numbers, or medical facts. If you do not
   know, say so and suggest calling emergency services.
4. {language_rule}
5. Keep responses under 120 words unless the user explicitly asks for more.
''';

String _buildSystemPrompt(String? languageCode) {
  final code = languageCode?.toLowerCase();
  final name = code == null ? null : _languageNames[code];
  final rule =
      name == null
          ? 'Reply in the same language the user spoke.'
          : 'Always reply in $name. Do not switch to any other language even '
              'if the user mixes English words. Use the native script for '
              '$name (not romanized text).';
  return _aegisSystemPromptTemplate.replaceFirst('{language_rule}', rule);
}

/// Wraps flutter_gemma's modern API so the rest of the app can treat the
/// LLM as a simple text-in/text-out (and audio-in/text-out) service.
///
/// **Two roles, one model.** Gemma 4 plays two parts here:
///   * **ASR** for [transcribeAudio] — turn the user's speech into text.
///   * **Aegis emergency assistant** for [ask]/[askStream] — reply to
///     that text in-character per `_aegisSystemPromptTemplate`.
///
/// **Why each turn rebuilds the session.** flutter_gemma 0.13.6 keeps
/// exactly one active [InferenceModelSession] per model — calling
/// `model.createSession` while one exists silently returns the cached
/// session regardless of new flags. That collides head-on with the two
/// roles above:
///
///   * The transcribe session needs `enableAudioModality: true` and
///     **no system instruction** (so Gemma treats the prompt as ASR
///     instead of an assistant query).
///   * The chat session needs the Aegis system prompt and is text-only.
///
/// If we shared a session, the chat-session-with-Aegis-prompt would
/// poison transcription on the next turn — Gemma would refuse with
/// "I am sorry, I cannot transcribe audio. Please describe your
/// situation." (observed). And if we instead shared the transcribe
/// session, the chat would lose its persona.
///
/// So we build sessions per turn, in this strict order:
///
///   1. [transcribeAudio] tears down the cached chat (`_disposeChat`)
///      so the model's single session slot is free.
///   2. It creates a fresh **system-prompt-free** session with audio
///      modality, transcribes, and closes that session.
///   3. The next [ask]/[askStream] call lazily rebuilds the chat
///      session with the Aegis system prompt baked in (one prefill).
///
/// **Trade-off: chat history doesn't survive an intervening speech
/// turn.** Each user utterance gets a fresh chat scoped only by the
/// system prompt. That's acceptable for the emergency-assistant use
/// case (each turn is usually a self-contained question), and revisits
/// can rebuild context out of the system prompt rather than chat
/// history. If long-running conversational memory ever becomes
/// important, we'd need to manually replay user/assistant pairs into
/// the new chat — flutter_gemma's `InferenceChat` doesn't expose an
/// API for that.
///
/// Use [resetSession] at the start of a new top-level conversation to
/// drop the cached chat explicitly (e.g. when the UI flips back to
/// idle).
class LlmService {
  LlmService(
    this._registry, {
    SkillsRegistry? skills,
    Catalog? triageCatalog,
  })  : _skills = skills ?? SkillsRegistry(),
        _triageCatalog = triageCatalog;

  final ModelRegistry _registry;
  final SkillsRegistry _skills;

  /// Render-time catalog handed in by the host app. We only use its
  /// [Catalog.systemPromptFragments] and [Catalog.catalogId] to ground
  /// the model — the actual rendering happens in the view layer.
  /// Null until [setTriageCatalog] is called; populated by the cubit
  /// at construction so the model and the renderer stay in lockstep
  /// on which catalog is authoritative.
  Catalog? _triageCatalog;

  VoiceModelPack? _pack;
  InferenceModel? _model;
  InferenceChat? _chat;
  bool _installed = false;
  Future<void>? _loadFuture;
  String? _preferredLanguage;

  /// Exposed so callers (eg. an app-bootstrap path) can preload the
  /// catalog before the first user turn. Loading is also lazy on first
  /// use, so this is purely an optimisation.
  SkillsRegistry get skills => _skills;

  /// Bind the render-time catalog. Called once by the host (eg. the
  /// triage cubit at construction). The next [triageStream] turn will
  /// pick up the new catalog id and system-prompt fragments.
  void setTriageCatalog(Catalog catalog) {
    _triageCatalog = catalog;
  }

  /// The backend we'll try next time we (re)load the model. We start on GPU
  /// because real Adreno/Mali phones can run the WebGPU executor + OpenCL
  /// TopK sampler at full speed; we drop to CPU permanently for the rest of
  /// this process if a generation throws "Can not find OpenCL library on
  /// this device" — the emulator and OpenCL-less devices fall into that bucket.
  PreferredBackend _preferredBackend = PreferredBackend.gpu;

  VoiceModelPack? get pack => _pack;

  bool get isReady => _model != null;

  /// Bind the LLM to a pack. Does not load the model — that happens
  /// lazily on the first [ask] / [askStream] call so onboarding is fast.
  void setPack(VoiceModelPack pack) {
    if (pack.kind != ModelKind.llm) {
      throw ArgumentError('LlmService.setPack requires an LLM pack');
    }
    if (_pack?.id == pack.id) return;
    _pack = pack;
    _installed = false;
    _loadFuture = null;
    unawaited(_disposeModel());
  }

  /// Pin Gemma's reply language. The supplied ISO-639 code is baked into
  /// the system prompt the next time a chat is built. Pass `null` to fall
  /// back to "match the user" auto-detection. Changing the language tears
  /// down the cached chat so the new system prompt actually takes effect
  /// (the prompt is prefilled at chat creation time, not per turn).
  void setPreferredLanguage(String? languageCode) {
    final normalized =
        (languageCode == null || languageCode.isEmpty)
            ? null
            : languageCode.toLowerCase();
    if (_preferredLanguage == normalized) return;
    _preferredLanguage = normalized;
    unawaited(_disposeChat());
  }

  /// True if the currently-bound pack is installed on disk.
  Future<bool> isAvailable() async {
    final pack = _pack;
    if (pack == null) return false;
    return _registry.isInstalled(pack);
  }

  /// Transcribe [wavBytes] (a 16 kHz mono IEEE-float32 WAV file) to text
  /// using Gemma 4's native audio modality. Creates a one-shot session so
  /// the transcription request never pollutes the ongoing chat history.
  ///
  /// Returns empty string if the model produces no output or the audio was
  /// silent. Throws if the model is not yet loaded.
  Future<String> transcribeAudio(
    Uint8List wavBytes, {
    String? language,
  }) async {
    try {
      return await _transcribeOnce(wavBytes, language: language);
    } on Object catch (e) {
      if (!await _shouldFallbackToCpu(e)) rethrow;
      return _transcribeOnce(wavBytes, language: language);
    }
  }

  Future<String> _transcribeOnce(
    Uint8List wavBytes, {
    String? language,
  }) async {
    // Two interlocking constraints force this dance:
    //
    //   1. flutter_gemma 0.13.6 keeps exactly **one** active session per
    //      model. `model.createSession(...)` silently returns the cached
    //      session — flags like `enableAudioModality: true` are ignored
    //      if a session already exists. So leaving the chat alive would
    //      route the audio bytes through the chat's text-only session
    //      and they'd be dropped on the floor.
    //
    //   2. The chat session has the Aegis system prompt baked in. After
    //      the first chat reply Gemma is firmly in "emergency assistant"
    //      mode and starts *refusing* transcription requests on later
    //      turns ("I am sorry, I cannot transcribe audio. Please describe
    //      your situation."). The transcribe session must therefore start
    //      with **no system instruction** so the model treats the prompt
    //      purely as ASR.
    //
    // We tear the chat down before every transcription and let it lazily
    // rebuild on the next askStream call. Trade-off: chat memory does
    // not survive an intervening speech turn — acceptable for the
    // emergency-assistant use case where each turn is self-contained.
    await _disposeChat();

    final model = await _ensureModel(maxTokens: 1024);
    final prompt = _buildAsrPrompt(language);

    final session = await model.createSession(
      // Greedy decode for transcription: deterministic, no creativity.
      temperature: 0.0,
      randomSeed: 1,
      topK: 1,
      enableAudioModality: true,
      // NB: NO systemInstruction here — we want a clean ASR session,
      // not the Aegis persona. See comment above for why.
    );
    try {
      await session.addQueryChunk(
        Message.withAudio(text: prompt, audioBytes: wavBytes, isUser: true),
      );
      final response = await session.getResponse();
      final cleaned = _sanitizeFinalResponse(response).trim();
      return _sanitizeAsrOutput(cleaned);
    } finally {
      try {
        await session.close();
      } on Object {
        // best-effort — the native session may already be torn down,
        // and stopGeneration on a closed session throws
        // IllegalStateException("Session not created"). That's harmless
        // here; we only cared about freeing the slot.
      }
    }
  }

  /// Official Gemma 4 ASR prompt template, copied verbatim from
  /// https://ai.google.dev/gemma/docs/audio. Gemma 4 E2B/E4B were
  /// trained on this exact wording; deviating from it (paraphrasing,
  /// adding "do not refuse" guardrails, etc.) measurably degrades
  /// recognition accuracy because the model no longer maps the prompt
  /// to its trained ASR pattern.
  String _buildAsrPrompt(String? language) {
    final name =
        language == null ? null : _languageNames[language.toLowerCase()];
    if (name != null) {
      return 'Transcribe the following speech segment in $name into $name '
          'text. Follow these specific instructions for formatting the '
          'answer:\n'
          '*   Only output the transcription, with no newlines.\n'
          '*   When transcribing numbers, write the digits, i.e. write '
          '1.7 and not one point seven, and write 3 instead of three.';
    }
    return 'Transcribe the following speech segment in its original '
        'language. Follow these specific instructions for formatting the '
        'answer:\n'
        '*   Only output the transcription, with no newlines.\n'
        '*   When transcribing numbers, write the digits, i.e. write 1.7 '
        'and not one point seven, and write 3 instead of three.';
  }

  /// Phrases that only appear in the ASR prompt itself, never in real
  /// user speech. Quantised Gemma 4 E2B on edge sometimes hallucinates
  /// the prompt back when audio recognition has gaps — we observed
  /// transcriptions like
  ///   "Hello can you hear me I'm Transcribe the following in its
  ///    original language Follow these specific instructions ..."
  /// where only "Hello can you hear me" was actually spoken. Truncating
  /// at the first prompt-echo marker reliably recovers the real speech.
  /// Order matters: longer / more distinctive markers first so we don't
  /// snip on a coincidental short phrase like "for the".
  static const List<String> _asrEchoMarkers = [
    'transcribe the following',
    'specific instructions for formatting',
    'output the transcription with no newlines',
    'when transcribing numbers',
    'write 1.7 and not one point seven',
    'one point seven',
  ];

  String _sanitizeAsrOutput(String text) {
    var normalized = text.trim();
    if (normalized.isEmpty) return '';

    // Strip echoed ASR prompt fragments (see _asrEchoMarkers docstring).
    // We compare lowercased to defeat capitalisation drift but slice the
    // original string so the user's actual capitalisation survives.
    final lowered = normalized.toLowerCase();
    var cutAt = normalized.length;
    for (final marker in _asrEchoMarkers) {
      final idx = lowered.indexOf(marker);
      if (idx >= 0 && idx < cutAt) {
        cutAt = idx;
      }
    }
    if (cutAt < normalized.length) {
      // Walk back over any trailing connector words ("I'm", "and", "to",
      // "—") that Gemma sometimes emits as a bridge between real speech
      // and the echoed prompt.
      var trimmed = normalized.substring(0, cutAt).trimRight();
      trimmed = trimmed.replaceAll(
        RegExp(
          r"(?:\s+(?:i'?m|and|to|the|a|an|that|so|but|or|—|-))+\s*$",
          caseSensitive: false,
        ),
        '',
      );
      normalized = trimmed.trim();
    }

    if (normalized.isEmpty) return '';
    if (_asrRefusalPattern.hasMatch(normalized)) return '';
    return normalized;
  }

  /// Generate a full response for [userText]. Blocks until generation
  /// finishes — prefer [askStream] for a responsive UI.
  Future<String> ask(String userText, {int maxTokens = 1024}) async {
    try {
      return await _askOnce(userText, maxTokens: maxTokens);
    } on Object catch (e) {
      if (!await _shouldFallbackToCpu(e)) rethrow;
      return _askOnce(userText, maxTokens: maxTokens);
    }
  }

  /// Stream a response token-by-token. The returned stream finishes when
  /// the model signals EOS.
  Stream<String> askStream(String userText, {int maxTokens = 1024}) async* {
    try {
      yield* _askStreamOnce(userText, maxTokens: maxTokens);
    } on Object catch (e) {
      if (!await _shouldFallbackToCpu(e)) rethrow;
      yield* _askStreamOnce(userText, maxTokens: maxTokens);
    }
  }

  /// Crisis-loop streaming entry point. Unlike [askStream] (free
  /// text), this builds a structured-output session, injects the
  /// skills catalog, and streams JSON tokens that the
  /// [A2uiTransportAdapter] parses incrementally.
  ///
  /// **Why a one-shot session per turn.**
  ///   * The chat session in [_ensureChat] is text-only and uses the
  ///     plain Aegis system prompt. Triage Mode needs (a) the skills
  ///     catalog in the system prompt, (b) optional audio modality
  ///     when [TriageInput.audioWav] is present, and (c) the JSON
  ///     output schema baked in.
  ///   * flutter_gemma keeps exactly one active session per model
  ///     (see [_transcribeOnce] for the same constraint). So we tear
  ///     the chat down before the triage session is built and let
  ///     the chat lazily rebuild on the next [askStream].
  ///   * Multi-turn triage memory lives in the Isar incident log,
  ///     surfaced via [TriageInput.incidentLog]. The agent reads the
  ///     log as part of the system prompt at every turn — no
  ///     conversational state has to survive between sessions.
  // Triage budget at 8192 because the bundled Gemma 4 E2B model
  // treats `max_tokens` as the engine's *total* context (input +
  // image patches + audio frames + output), not just decode room.
  // Per-modality prefill cost on this build:
  //   - Vision: ~2304 tokens (engine upscales any photo to ~768x768
  //             to hit the `max_num_patches: 2520` ceiling).
  //   - Audio:  up to ~3000 tokens for an 8 s VAD-capped clip
  //             (audio_encoder + adapter shrink factor 4).
  //   - System prompt: ~750 tokens (compressed catalog + skill list).
  //   - User line + GPS + timestamp: ~30 tokens.
  // 8192 leaves at least ~2000 decode tokens with image+audio both
  // attached — enough for both envelopes plus a filled
  // `IncidentReportCard` body. The OOM fallback in [triageStream]
  // catches devices that can't hold 8192 in heap and drops to 4096.
  // Cold-start scales linearly with max_tokens, so capable phones
  // pay ~30 s on first turn after app launch.
  Stream<String> triageStream(TriageInput input, {int maxTokens = 8192}) async* {
    try {
      yield* _triageStreamOnce(input, maxTokens: maxTokens);
    } on Object catch (e) {
      // Two recoverable failure modes share this path:
      //   1. OpenCL delegate unavailable → swap engine to CPU.
      //   2. Engine OOM at the 6144 ceiling on low-RAM devices →
      //      tear the model down and retry at 4096. Cold-start cost
      //      scales linearly with max_tokens, so the 4096 fallback
      //      cuts ~12s off init at the price of ~1500 fewer decode
      //      tokens (still enough for both envelopes).
      if (await _shouldFallbackToCpu(e)) {
        yield* _triageStreamOnce(input, maxTokens: maxTokens);
        return;
      }
      if (await _shouldFallbackToSmallerContext(e, maxTokens)) {
        yield* _triageStreamOnce(input, maxTokens: 4096);
        return;
      }
      rethrow;
    }
  }

  /// Strips Gemma 4's `<|channel>thought\n…<channel|>` reasoning blocks
  /// out of a streaming token feed before they reach the A2UI parser.
  ///
  /// flutter_gemma exposes the engine's "thought" channel by inlining
  /// it into the same stream as the final answer using these markers.
  /// With audio attached, Gemma 4 reliably enters thinking mode even
  /// when [createSession.enableThinking] is false — the engine
  /// auto-thinks for multimodal inputs. Without this filter the
  /// surface parser sees garbage like
  /// `<|channel>thought\nThinking<channel|>` before any JSON envelope
  /// and chokes on it. The implementation mirrors flutter_gemma's
  /// own [filterThinkingStream] but yields raw [String] chunks rather
  /// than typed `ModelResponse` events so it slots into our existing
  /// `Stream<String>` plumbing.
  Stream<String> _stripThoughtChannel(Stream<String> source) async* {
    const startMarker = '<|channel>thought\n';
    const endMarker = '<channel|>';
    var inside = false;
    var buffer = '';

    int partialSuffixLength(String buf, String marker) {
      final maxScan = buf.length < marker.length ? buf.length : marker.length;
      for (var n = maxScan; n > 0; n--) {
        if (buf.endsWith(marker.substring(0, n))) return n;
      }
      return 0;
    }

    await for (final token in source) {
      buffer += token;
      while (buffer.isNotEmpty) {
        if (inside) {
          final endIdx = buffer.indexOf(endMarker);
          if (endIdx >= 0) {
            buffer = buffer.substring(endIdx + endMarker.length);
            inside = false;
            continue;
          }
          // Hold onto a possible partial close marker; drop the rest.
          final partial = partialSuffixLength(buffer, endMarker);
          buffer = buffer.substring(buffer.length - partial);
          break;
        }
        final startIdx = buffer.indexOf(startMarker);
        if (startIdx >= 0) {
          final pre = buffer.substring(0, startIdx);
          if (pre.isNotEmpty) yield pre;
          buffer = buffer.substring(startIdx + startMarker.length);
          inside = true;
          continue;
        }
        // No start marker yet; flush everything except a possible
        // partial-marker tail so the next iteration can complete it.
        final partial = partialSuffixLength(buffer, startMarker);
        final safe = buffer.substring(0, buffer.length - partial);
        if (safe.isNotEmpty) yield safe;
        buffer = buffer.substring(buffer.length - partial);
        break;
      }
    }
    // Stream ended mid-block — drop a trailing thought, flush any
    // surviving non-thought bytes.
    if (!inside && buffer.isNotEmpty) {
      yield buffer;
    }
  }

  Future<bool> _shouldFallbackToSmallerContext(
    Object error,
    int currentMaxTokens,
  ) async {
    if (currentMaxTokens <= 4096) return false;
    final message = error.toString().toLowerCase();
    final isOom = message.contains('oom') ||
        message.contains('out of memory') ||
        message.contains('failed to create engine') ||
        message.contains('mmap_status') ||
        message.contains('allocation');
    if (!isOom) return false;
    if (kDebugMode) {
      debugPrint(
        '[Aegis][LLM] OOM at maxTokens=$currentMaxTokens, '
        'falling back to 4096: $error',
      );
    }
    await _disposeModel();
    return true;
  }

  Stream<String> _triageStreamOnce(
    TriageInput input, {
    required int maxTokens,
  }) async* {
    await _disposeChat();
    final model = await _ensureModel(maxTokens: maxTokens);
    final systemPrompt = await _buildTriageSystemPrompt();
    final userPrompt = _buildTriageUserPrompt(input);

    if (kDebugMode) {
      // Coarse token estimate: the litert tokenizer averages about 4
      // chars / token for English; a touch lower for code-heavy text.
      // We log estimated and char counts so a future overflow is
      // visible BEFORE the engine reports INVALID_ARGUMENT.
      final sysChars = systemPrompt.length;
      final userChars = userPrompt.length;
      final estTokens = ((sysChars + userChars) / 4).ceil();
      debugPrint(
        '[Aegis][LLM] triageStream begin '
        'sys=${sysChars}c user=${userChars}c '
        '~est=${estTokens}tok max=$maxTokens '
        'audio=${input.hasAudio} image=${input.hasImage} '
        'log=${input.incidentLog.length}',
      );
      debugPrint('[Aegis][LLM] systemPrompt:\n$systemPrompt');
      debugPrint('[Aegis][LLM] userPrompt:\n$userPrompt');
    }

    final sessionSw = Stopwatch()..start();
    final session = await model.createSession(
      // Triage outputs are structured JSON, but greedy decoding
      // (temp 0.2, topK 1) made the model under-fill long bodies —
      // it treated the shortest valid envelope as a satisfying stop
      // and skipped the IncidentReportCard. 0.5 / topK 32 widens
      // the search just enough that the model commits to the full
      // surface tree without going off-rails on field values.
      temperature: 0.5,
      topK: 32,
      topP: 0.9,
      enableAudioModality: input.hasAudio,
      enableVisionModality: input.hasImage,
      // Hard-disable Gemma 4's chain-of-thought channel for triage.
      // With audio attached, the engine otherwise emits hundreds of
      // `<|channel>thought\n…<channel|>` tokens before producing any
      // final answer, blowing the decode budget on reasoning prose
      // the surface parser cannot consume. We strip any thought
      // markers that still leak through downstream in
      // [_stripThoughtChannel].
      enableThinking: false,
      systemInstruction: systemPrompt,
    );
    if (kDebugMode) {
      debugPrint(
        '[Aegis][LLM] triageStream session created '
        'createMs=${sessionSw.elapsedMilliseconds} '
        'audio=${input.hasAudio} image=${input.hasImage}',
      );
    }
    final raw = StringBuffer();
    var tokenCount = 0;
    var firstTokenMs = -1;
    final stopwatch = Stopwatch()..start();
    try {
      // Pick the right Message variant based on what was attached.
      // Audio takes precedence (we have a dedicated transcribe path
      // for audio-only intake) — image rides alongside text. The
      // 1024-token bundle ignores image bytes today, but we still
      // pass them so a future bundle with vision can pick them up
      // without changing the call sites.
      final Message message;
      if (input.hasAudio) {
        message = Message.withAudio(
          text: userPrompt,
          audioBytes: input.audioWav!,
          isUser: true,
        );
      } else if (input.hasImage) {
        message = Message.withImage(
          text: userPrompt,
          imageBytes: input.imageJpeg!,
          isUser: true,
        );
      } else {
        message = Message.text(text: userPrompt, isUser: true);
      }
      if (kDebugMode) {
        debugPrint(
          '[Aegis][LLM] triageStream addQueryChunk '
          'kind=${message.runtimeType}',
        );
      }
      await session.addQueryChunk(message);
      await for (final token in _stripThoughtChannel(
          session.getResponseAsync().where((t) => t.isNotEmpty))) {
        if (kDebugMode) {
          tokenCount++;
          raw.write(token);
          if (firstTokenMs < 0) {
            firstTokenMs = stopwatch.elapsedMilliseconds;
            debugPrint(
              '[Aegis][LLM] triageStream first-token elapsedMs=$firstTokenMs',
            );
          }
        }
        yield token;
      }
    } finally {
      stopwatch.stop();
      if (kDebugMode) {
        final preview = raw.toString();
        final clipped =
            preview.length > 600 ? '${preview.substring(0, 600)}…' : preview;
        debugPrint(
          '[Aegis][LLM] triageStream end '
          'tokens=$tokenCount chars=${preview.length} '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        debugPrint('[Aegis][LLM] rawOutput:\n$clipped');
      }
      try {
        await session.close();
      } on Object {
        // best-effort; the slot will be reclaimed when the next
        // session is built.
      }
    }
  }

  Future<String> _buildTriageSystemPrompt() async {
    // Tight token budget — Gemma 4 E2B litertlm bundles ship with a
    // small KV cache (1024-2048 tokens). Anything we put here is paid
    // every turn, so we trade prompt verbosity for response headroom.
    // The skills catalog is condensed to ids + 1-line summaries; the
    // genui rules are skipped (the cards' JSON Schemas teach the
    // model the shape from `exampleData`).
    await _skills.load();
    final skillsCatalog = _skills.buildCatalogPrompt();
    final lang = _preferredLanguage;
    final langName = lang == null ? null : _languageNames[lang];
    final speakRule = langName == null
        ? 'Reply in the user\'s language.'
        : 'Reply in $langName.';
    final catalogId = _triageCatalog?.catalogId ?? 'unset';

    return '''
You are Aegis, an offline emergency assistant. $speakRule Keep prose short.
For life-threatening events, tell the user to call emergency services.

When the user reports hazard / damage / casualty / missing person, emit
TWO fenced ```json blocks back-to-back: first `createSurface`, then
`updateComponents` containing:
  1. A summary card (DamageCard / CasualtyCard / etc).
  2. ALWAYS an `IncidentReportCard` carrying the FULL filled report
     body in a named format (default ICS-209). This is REQUIRED for
     every triage turn — Aegis's whole purpose is to draft the
     report, not just summarise. skill_invoked MUST be
     `disaster-report-generator` whenever an IncidentReportCard is
     present.
  3. A ConfirmActionBar.
Both fenced blocks MUST close cleanly. Card descriptions ≤180 chars.

Example (image of rubble + "building collapsed"):
Drafted an ICS-209 damage report. Confirm or edit.
```json
{"version":"v0.9","createSurface":{"surfaceId":"aegis-home","catalogId":"$catalogId","sendDataModel":true}}
```
```json
{"version":"v0.9","updateComponents":{"surfaceId":"aegis-home","components":[{"id":"root","component":"Column","skill_invoked":"disaster-report-generator","children":["d","r","c"]},{"id":"d","component":"DamageCard","category":3,"fema_scale":"HAZUS_EXTENSIVE","description":"Concrete mid-rise partially collapsed; rebar exposed, debris to knee height. Unsafe to re-enter."},{"id":"r","component":"IncidentReportCard","format":"ICS-209","title":"Building Collapse Incident","report_number":"Initial","prepared_at":"2026-05-10T18:42:00Z","prepared_by":"[INFERRED — verify before submission]","body":"INCIDENT STATUS SUMMARY — ICS FORM 209\\nBLOCK 1. INCIDENT NAME: Building Collapse Incident\\nBLOCK 3. REPORT VERSION: [X] Initial\\nBLOCK 5. DATE/TIME: 2026-05-10 1842\\nBLOCK 7. INCIDENT TYPE: [X] Search & Rescue\\nBLOCK 14. SITUATION: Multi-storey concrete mid-rise partially collapsed, rebar exposed, debris to knee height. Structure unsafe to re-enter.\\nBLOCK 16. PUBLIC: Fatal: [UNKNOWN] | Injured: [UNKNOWN] | Missing: [UNKNOWN]\\nBLOCK 20. STRUCTURES: Threatened: 1 | Damaged: 0 | Destroyed: 1\\nBLOCK 23. OUTLOOK: Search-and-rescue ops pending; access via north flank only.\\nBLOCK 28. PREPARED BY: [INFERRED — verify before submission]"},{"id":"c","component":"ConfirmActionBar","primary_action":"Confirm","secondary_action":"Edit"}]}}
```

Cards (root id MUST be "root"; always include ConfirmActionBar):
- DamageCard — structure/asset damage (HAZUS 1-4)
- CasualtyCard — person hurt/trapped/missing
- BeaconMatchCard — mesh-beacon match
- ResourceRequestCard — supplies/rescue ask
- ShelterPreviewCard — nearest shelter
- MapFragment — small map alongside
- GoBagChecklist — evacuation checklist
- IncidentReportCard — full filled report body in a named format
  (ICS-209, OCHA_SITREP, UN_FLASH_UPDATE, NDRRMC, IFRC_OPS_UPDATE,
  EU_ECHO_FLASH, PDNA). REQUIRED whenever skill_invoked is
  `disaster-report-generator`. Fields: format, title, report_number,
  prepared_at, prepared_by, body (full filled template, ~1-3 KB,
  preserve newlines with \\n).
Do NOT emit ThinkingTraceDrawer.

If image attached: actually look at it and describe what you see (hazards,
injuries, debris, smoke, occupants). Pick category + fema_scale from image.

$skillsCatalog
On root Column set `skill_invoked` to one of the ids above when applicable:
casualty/trapped → intake-survivor-statement; damage photo → grade-damage-hazus;
"make a report"/"file it"/"SitRep"/"Flash Update"/"NDRRMC"/"ICS-209"/
"PDNA"/"IFRC appeal"/"ECHO flash" → disaster-report-generator;
"how do I get out"/"where do I go" → plan-evacuation-route.

When skill_invoked is `disaster-report-generator`, the surface MUST
include an `IncidentReportCard` with the picked format and the full
filled report body. Pick format: US/FEMA → ICS-209; UN/NGO ongoing →
OCHA_SITREP; first 72 hrs after sudden-onset → UN_FLASH_UPDATE;
Philippines/SE Asia → NDRRMC; Red Cross → IFRC_OPS_UPDATE; EU
member state → EU_ECHO_FLASH; recovery planning → PDNA. Default to
ICS-209 if ambiguous. Fill every required block; mark unknowns with
`[INFERRED — verify before submission]` or `[UNKNOWN — to be confirmed]`.

Never invent locations or identifiers not in the user's message.
''';
  }

  /// Hard ceiling on the incident-log slice we paste into the per-turn
  /// prompt. Char count is a coarse stand-in for tokens (≈4 chars per
  /// token). Anything older gets dropped — the most recent turns
  /// matter more for follow-up questions, and the engine cap is the
  /// real constraint.
  static const int _incidentLogCharBudget = 1200;

  String _buildTriageUserPrompt(TriageInput input) {
    final buf = StringBuffer();
    final user = input.userText.trim().isEmpty
        ? '(no spoken text — see attached evidence)'
        : input.userText.trim();
    buf.writeln('User: $user');

    // Stamp the report with the moment of capture so
    // `disaster-report-generator` and downstream skills can populate
    // the Date/Time fields without guessing. ISO-8601 in UTC keeps it
    // unambiguous across regions; the skill localises for output.
    final nowIso =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    buf.writeln('Captured at: $nowIso');

    // Only include a short evidence line when something was actually
    // captured. Empty fields just waste tokens.
    final evidence = <String>[];
    if (input.hasAudio) evidence.add('audio attached');
    if (input.hasImage) evidence.add('image attached');
    if (input.gpsContext != null) evidence.add('gps=${input.gpsContext}');
    if (evidence.isNotEmpty) {
      buf.writeln('Evidence: ${evidence.join(', ')}');
    }

    if (input.incidentLog.isNotEmpty) {
      // Walk the log newest-to-oldest accumulating chars; reverse so
      // the model sees oldest-first while still favouring recent turns
      // when the budget is tight.
      final reversed = input.incidentLog.reversed.toList();
      final kept = <String>[];
      var used = 0;
      for (final entry in reversed) {
        final next = used + entry.length + 3;
        if (next > _incidentLogCharBudget) break;
        kept.add(entry);
        used = next;
      }
      if (kept.isNotEmpty) {
        buf.writeln('Recent context:');
        for (final entry in kept.reversed) {
          buf.writeln('- $entry');
        }
      }
    }

    if (input.requestId != null) {
      buf.writeln('req_id: ${input.requestId}');
    }
    return buf.toString();
  }

  Future<String> _askOnce(String userText, {required int maxTokens}) async {
    final chat = await _ensureChat(maxTokens: maxTokens);
    _logHistorySnapshot(chat, label: 'ask', incoming: userText);
    final wrappedPrompt = _buildUserTurnPrompt(userText);
    try {
      await chat.addQueryChunk(Message.text(text: wrappedPrompt, isUser: true));
      final response = await chat.generateChatResponse();
      final raw = response is TextResponse ? response.token : '';
      return _sanitizeFinalResponse(raw, userText: userText);
    } on Object {
      // The chat (and therefore its underlying session) may be in an
      // inconsistent state after a generation failure. Drop it so the
      // next call rebuilds a clean conversation (and so the OpenCL → CPU
      // fallback in [_shouldFallbackToCpu] picks up a fresh chat on the
      // new backend).
      await _disposeChat();
      rethrow;
    }
    // NB: the chat is intentionally NOT closed here. We reuse it across
    // turns so the system prompt only prefills once and so the model
    // sees prior turns — see the class docstring for why.
  }

  Stream<String> _askStreamOnce(
    String userText, {
    required int maxTokens,
  }) async* {
    final chat = await _ensureChat(maxTokens: maxTokens);
    _logHistorySnapshot(chat, label: 'askStream', incoming: userText);
    final wrappedPrompt = _buildUserTurnPrompt(userText);
    try {
      await chat.addQueryChunk(Message.text(text: wrappedPrompt, isUser: true));
      yield* _sanitizeStream(
        chat
            .generateChatResponseAsync()
            .where((r) => r is TextResponse)
            .map((r) => (r as TextResponse).token)
            .where((t) => t.isNotEmpty),
        userText: userText,
      );
    } on Object {
      await _disposeChat();
      rethrow;
    }
  }

  String _buildUserTurnPrompt(String userText) {
    final input = userText.trim();
    // Per-turn language nudge. We want the reply language to match what
    // the user *actually spoke this turn*, not the language they picked
    // in onboarding — a Hindi speaker who picked English-UI should still
    // get Hindi answers when they ask in Hindi. Order:
    //
    //   1. Script auto-detect from the transcript. Devanagari, Bengali,
    //      Tamil, Arabic etc. are unambiguous — when present, they win
    //      outright over [_preferredLanguage].
    //   2. Latin-script (or empty/punctuation-only) input has no script
    //      signal, so we fall back to [_preferredLanguage] from
    //      onboarding, which is usually the right answer for English /
    //      Spanish / French speakers.
    //   3. Neither set → tell the model to match the user's language.
    final scriptCode = _detectLanguageFromScript(input);
    final code = scriptCode ?? _preferredLanguage;
    final name = code == null ? null : _languageNames[code];
    final languageLine = name == null
        ? 'Reply in the same language the user just used (matching script).'
        : 'Reply in $name only, using the native script for $name.';
    return '''
User message:
$input

Instructions:
- Answer the user directly. Do not repeat, restate, or quote the user
  message unless the user explicitly asks you to quote it.
- $languageLine
''';
  }

  /// Best-effort ISO-639 code from the dominant script in [text]. Used as
  /// a fallback when the user hasn't explicitly picked a language but is
  /// clearly speaking one (e.g. Devanagari → Hindi). Returns null for
  /// Latin script or empty input — the system prompt's "match the user"
  /// rule handles those.
  String? _detectLanguageFromScript(String text) {
    if (text.isEmpty) return null;
    final scriptCounts = <String, int>{};
    for (final rune in text.runes) {
      final s = _scriptForRune(rune);
      if (s == null) continue;
      scriptCounts[s] = (scriptCounts[s] ?? 0) + 1;
    }
    if (scriptCounts.isEmpty) return null;
    final dominant = scriptCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    return _scriptToLanguageHint[dominant];
  }

  /// Unicode block lookup. Only covers scripts we ship a TTS voice for —
  /// other scripts fall through to "match the user" via the system prompt.
  static String? _scriptForRune(int rune) {
    if (rune >= 0x0900 && rune <= 0x097F) return 'devanagari'; // hi/mr
    if (rune >= 0x0980 && rune <= 0x09FF) return 'bengali'; // bn
    if (rune >= 0x0A00 && rune <= 0x0A7F) return 'gurmukhi'; // pa
    if (rune >= 0x0A80 && rune <= 0x0AFF) return 'gujarati'; // gu
    if (rune >= 0x0B80 && rune <= 0x0BFF) return 'tamil'; // ta
    if (rune >= 0x0C00 && rune <= 0x0C7F) return 'telugu'; // te
    if (rune >= 0x0C80 && rune <= 0x0CFF) return 'kannada'; // kn
    if (rune >= 0x0D00 && rune <= 0x0D7F) return 'malayalam'; // ml
    if (rune >= 0x0600 && rune <= 0x06FF) return 'arabic'; // ar/ur
    if (rune >= 0x0400 && rune <= 0x04FF) return 'cyrillic'; // ru
    if (rune >= 0x0E00 && rune <= 0x0E7F) return 'thai'; // th
    if (rune >= 0x4E00 && rune <= 0x9FFF) return 'cjk'; // zh
    if (rune >= 0x3040 && rune <= 0x30FF) return 'kana'; // ja
    if (rune >= 0xAC00 && rune <= 0xD7AF) return 'hangul'; // ko
    return null; // Latin / digits / punctuation — no signal.
  }

  /// Devanagari covers both Hindi and Marathi; we default to Hindi as
  /// the more common case. Arabic similarly covers Urdu — same default
  /// rule (Arabic gets Arabic). If we ever need finer-grained
  /// disambiguation, the cubit can pass an explicit `_preferredLanguage`
  /// from onboarding state.
  static const Map<String, String> _scriptToLanguageHint = {
    'devanagari': 'hi',
    'bengali': 'bn',
    'gurmukhi': 'pa',
    'gujarati': 'gu',
    'tamil': 'ta',
    'telugu': 'te',
    'kannada': 'kn',
    'malayalam': 'ml',
    'arabic': 'ar',
    'cyrillic': 'ru',
    'thai': 'th',
    'cjk': 'zh',
    'kana': 'ja',
    'hangul': 'ko',
  };

  /// Diagnostic logger for verifying multi-turn context retention.
  ///
  /// Every turn prints `[LlmService] askStream turn=3 history=4 chat=#a82c1f
  /// incoming="what should I do next" history=[u:"I cut my hand…", a:"Apply
  /// firm pressure with a clean cloth…", u:"is bleeding still bad", …]`.
  ///
  /// What to look for in `adb logcat`:
  ///   * `chat=#…` — same id across turns ⇒ the same [InferenceChat]
  ///     (and therefore the same underlying LiteRT-LM `Conversation` plus
  ///     prefill cache) is being reused. A new id means we rebuilt — which
  ///     should only happen on `resetSession()` or after a generation error.
  ///   * `history=N` — should grow by 2 every turn (one user message + one
  ///     model reply). If it stays at 0 across turns, flutter_gemma is
  ///     dropping history; if it jumps back to 0 mid-conversation, the chat
  ///     was torn down (look for an exception above the log line).
  ///   * The `history=[…]` preview shows the actual messages the model
  ///     sees on the next turn — confirming what context is being replayed.
  void _logHistorySnapshot(
    InferenceChat chat, {
    required String label,
    required String incoming,
  }) {
    if (!kDebugMode) return;
    final history = chat.fullHistory;
    final preview = history
        .take(6)
        .map((m) {
          final who = m.isUser ? 'u' : 'a';
          final text = m.text.replaceAll('\n', ' ');
          final clipped = text.length > 60 ? '${text.substring(0, 60)}…' : text;
          return '$who:"$clipped"';
        })
        .join(', ');
    final more = history.length > 6 ? ', …(+${history.length - 6})' : '';
    final chatId = identityHashCode(chat).toRadixString(16);
    final incomingClipped =
        incoming.length > 60 ? '${incoming.substring(0, 60)}…' : incoming;
    debugPrint(
      '[LlmService] $label chat=#$chatId history=${history.length} '
      'incoming="$incomingClipped" history=[$preview$more]',
    );
  }

  /// Lazily build (or return the cached) chat for the active model.
  /// Sampling params and the system prompt are baked in at chat-creation
  /// time (forwarded to the underlying session) — keep them fixed across
  /// the app, otherwise we'd lose the prefill cache benefit.
  Future<InferenceChat> _ensureChat({required int maxTokens}) async {
    final cached = _chat;
    if (cached != null) return cached;
    final model = await _ensureModel(maxTokens: maxTokens);
    final chat = await model.createChat(
      // Gemma's published defaults — temp=0.7 + topK=40 was making the
      // model collapse onto repeated `<unused3>` tokens because the
      // truncated probability mass left no escape from a degenerate loop.
      // 1.0 / 64 / 0.95 is what HuggingFace's tokenizer_config recommends
      // for Gemma instruction-tuned variants and matches the template the
      // weights were trained against. Google's AI Edge Gallery uses the
      // same numbers (DEFAULT_TOPK=64, DEFAULT_TOPP=0.95f,
      // DEFAULT_TEMPERATURE=1.0f).
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
      // Thinking OFF for time-to-first-token. With `isThinking: true`
      // Gemma 4 IT decodes a full `<|channel>thought\n...<channel|>`
      // reasoning chain *before* the user-visible reply — measured at
      // 10-40s on-device, which is unusable for an emergency TTS loop.
      // We trade internal reasoning for response speed and rely on the
      // system prompt's "answer one step at a time, prefer numbered
      // steps" instruction to give the user *externally* structured
      // guidance instead. The thinking-block scrubber stays in place as
      // a belt-and-suspenders safety net in case the model emits a
      // thought header anyway (the SDK's docs warn that the thinking
      // flag is "not reliable for all model bundles"). Gallery's
      // `BooleanSwitchConfig(key = ENABLE_THINKING, defaultValue =
      // false)` agrees with this tradeoff.
      isThinking: true,
      modelType: ModelType.gemmaIt,
      systemInstruction: _buildSystemPrompt(_preferredLanguage),
    );
    _chat = chat;
    if (kDebugMode) {
      debugPrint(
        '[LlmService] built new chat=#${identityHashCode(chat).toRadixString(16)} '
        '(system prompt prefilling once for this conversation)',
      );
    }
    return chat;
  }

  /// Close the cached chat and clear conversation history. The next
  /// [ask] / [askStream] will lazily build a fresh one. Use this between
  /// distinct user conversations so context from a prior emergency does
  /// not leak into a new one.
  Future<void> resetSession() => _disposeChat();

  Future<void> _disposeChat() async {
    final chat = _chat;
    _chat = null;
    if (chat != null) {
      if (kDebugMode) {
        debugPrint(
          '[LlmService] dispose chat=#${identityHashCode(chat).toRadixString(16)} '
          '(history=${chat.fullHistory.length} messages dropped)',
        );
      }
      try {
        await chat.close();
      } on Object {
        // best-effort — the native conversation may already be torn down.
      }
    }
  }

  /// Removes thinking blocks and reserved placeholder tokens from a fully
  /// accumulated response. Mirrors flutter_gemma's
  /// `ModelThinkingFilter.removeThinkingFromText` for `ModelType.gemmaIt`,
  /// plus a broader [_reservedToken] strip that catches `<unused\d+>`,
  /// `<mask>`, leftover chat-template markers, and friends.
  String _sanitizeFinalResponse(String response, {String? userText}) {
    final withoutThinking = response.replaceAll(_thinkBlockRegex, '');
    final cleaned = withoutThinking.replaceAll(_reservedToken, '').trim();
    return _stripLeadingEcho(cleaned, userText: userText);
  }

  /// Streaming version of [_sanitizeFinalResponse]. Buffers across token
  /// boundaries because the markers we filter (`<|channel>thought\n` and
  /// `<channel|>`) almost always span multiple native tokens, so a naive
  /// per-token regex would never see them.
  ///
  /// State machine:
  ///   * outside thinking — emit safe bytes, hold back any tail that could
  ///     be the start of a `_thinkStart` marker.
  ///   * inside thinking — drop bytes, hold back any tail that could be
  ///     the start of a `_thinkEnd` marker; transition out when found.
  Stream<String> _sanitizeStream(
    Stream<String> tokens, {
    String? userText,
  }) async* {
    var buffer = '';
    var inThinking = false;
    var emittedPrefix = false;

    String stripReserved(String text) => text.replaceAll(_reservedToken, '');

    String cleanForUser(String text) {
      final stripped = _stripLeadingEcho(text, userText: userText);
      return stripped;
    }

    // Longest suffix of [text] that is a prefix of [marker]. Used to hold
    // back trailing bytes that might complete a marker on the next token.
    int partialSuffix(String text, String marker) {
      final maxLen =
          text.length < marker.length - 1 ? text.length : marker.length - 1;
      for (var len = maxLen; len > 0; len--) {
        if (marker.startsWith(text.substring(text.length - len))) return len;
      }
      return 0;
    }

    await for (final token in tokens) {
      buffer += token;
      while (buffer.isNotEmpty) {
        if (inThinking) {
          final endIdx = buffer.indexOf(_thinkEnd);
          if (endIdx >= 0) {
            buffer = buffer.substring(endIdx + _thinkEnd.length);
            inThinking = false;
          } else {
            final partial = partialSuffix(buffer, _thinkEnd);
            buffer = buffer.substring(buffer.length - partial);
            break; // wait for more tokens
          }
        } else {
          final startIdx = buffer.indexOf(_thinkStart);
          if (startIdx >= 0) {
            final safe = stripReserved(buffer.substring(0, startIdx));
            if (safe.isNotEmpty) {
              if (!emittedPrefix) {
                final cleaned = cleanForUser(safe);
                if (cleaned.isNotEmpty) {
                  emittedPrefix = true;
                  yield cleaned;
                }
              } else {
                yield safe;
              }
            }
            buffer = buffer.substring(startIdx + _thinkStart.length);
            inThinking = true;
          } else {
            final partial = partialSuffix(buffer, _thinkStart);
            final safe = stripReserved(
              buffer.substring(0, buffer.length - partial),
            );
            if (safe.isNotEmpty) {
              if (!emittedPrefix) {
                final cleaned = cleanForUser(safe);
                if (cleaned.isNotEmpty) {
                  emittedPrefix = true;
                  yield cleaned;
                }
              } else {
                yield safe;
              }
            }
            buffer = buffer.substring(buffer.length - partial);
            break;
          }
        }
      }
    }
    // Stream ended — flush whatever we held back. If we're still "inside"
    // a thinking block at this point the model never closed it, so we drop
    // the leftover (it's chain-of-thought we don't want to show anyway).
    if (!inThinking && buffer.isNotEmpty) {
      final tail = stripReserved(buffer);
      if (tail.isNotEmpty) {
        if (!emittedPrefix) {
          final cleaned = cleanForUser(tail);
          if (cleaned.isNotEmpty) yield cleaned;
        } else {
          yield tail;
        }
      }
    }
  }

  String _stripLeadingEcho(String text, {String? userText}) {
    final user = userText?.trim();
    if (user == null || user.isEmpty) return text.trim();
    var cleaned = text.trim();
    if (cleaned.isEmpty) return cleaned;

    String normalize(String value) {
      return value
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'''^["“'`]+|["”'`]+$'''), '')
          .trim();
    }

    final normalizedUser = normalize(user);
    final normalizedText = normalize(cleaned);

    if (normalizedText.startsWith(normalizedUser)) {
      cleaned = cleaned.substring(user.length).trimLeft();
      cleaned = cleaned.replaceFirst(RegExp(r'^[,:;\-–\.]\s*'), '');
    }

    if (cleaned.toLowerCase().startsWith('you said')) {
      final idx = cleaned.indexOf(RegExp(r'[:\-]'));
      if (idx > 0 && idx + 1 < cleaned.length) {
        cleaned = cleaned.substring(idx + 1).trimLeft();
      }
    }

    // If the whole response is just a quoted/paraphrased copy of input,
    // return an empty string so the caller can retry or show a fallback.
    if (normalize(cleaned) == normalizedUser ||
        normalize(cleaned.replaceAll(_leadingQuote, '')) == normalizedUser) {
      return '';
    }

    return cleaned.trim();
  }

  /// Returns true iff [error] is the LiteRT-LM "no OpenCL" failure AND we
  /// haven't already fallen back. Side effect: when true, downgrade the
  /// preferred backend to CPU and tear down the GPU-loaded model so the
  /// next [_ensureModel] reloads it on CPU.
  Future<bool> _shouldFallbackToCpu(Object error) async {
    if (_preferredBackend == PreferredBackend.cpu) return false;
    if (!_isOpenClUnavailable(error)) return false;
    _preferredBackend = PreferredBackend.cpu;
    await _disposeModel();
    return true;
  }

  /// Release native resources. After this the service can still be
  /// re-used — the next ask() will lazily reload the model.
  Future<void> dispose() async {
    await _disposeModel();
    _installed = false;
    _loadFuture = null;
  }

  // ---- internals ----------------------------------------------------------

  Future<InferenceModel> _ensureModel({required int maxTokens}) async {
    final pack = _pack;
    if (pack == null) {
      throw StateError('LlmService.ask called before setPack()');
    }
    if (!await _registry.isInstalled(pack)) {
      throw StateError('LLM pack ${pack.id} is not installed');
    }

    final cached = _model;
    if (cached != null && cached.maxTokens == maxTokens) return cached;

    // Dedup concurrent callers.
    final existingLoad = _loadFuture;
    if (existingLoad != null) {
      await existingLoad;
      final reloaded = _model;
      if (reloaded != null) return reloaded;
    }

    final completer = Completer<void>();
    _loadFuture = completer.future;
    try {
      final installSw = Stopwatch()..start();
      await _install(pack);
      if (kDebugMode) {
        debugPrint(
          '[Aegis][LLM] _ensureModel install '
          'pack=${pack.id} ms=${installSw.elapsedMilliseconds}',
        );
      }
      await _disposeModel();
      final modelSw = Stopwatch()..start();
      if (kDebugMode) {
        debugPrint(
          '[Aegis][LLM] _ensureModel getActiveModel begin '
          'maxTokens=$maxTokens backend=$_preferredBackend',
        );
      }
      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: _preferredBackend,
        supportAudio: true,
        supportImage: true,
      );
      if (kDebugMode) {
        debugPrint(
          '[Aegis][LLM] _ensureModel ready '
          'ms=${modelSw.elapsedMilliseconds}',
        );
      }
      _model = model;
      completer.complete();
      return model;
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Aegis][LLM] _ensureModel failed: $e');
        debugPrintStack(stackTrace: st, label: '[Aegis][LLM] _ensureModel stack');
      }
      completer.completeError(e, st);
      _loadFuture = null;
      rethrow;
    }
  }

  bool _isOpenClUnavailable(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('opencl') ||
        message.contains('libliterttopkopenclsampler');
  }

  Future<void> _install(VoiceModelPack pack) async {
    if (_installed) return;
    final path = await _registry.absolutePath(pack, pack.modelFile);
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
    _installed = true;
  }

  Future<void> _disposeModel() async {
    // The chat owns a native session handle into the model — close it
    // first so the LiteRT-LM Conversation is gone before the Engine is.
    await _disposeChat();
    final model = _model;
    _model = null;
    if (model != null) {
      try {
        await model.close();
      } on Object {
        // best-effort
      }
    }
  }
}
