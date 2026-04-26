import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'model_pack.dart';
import 'model_registry.dart';

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

/// Emergency-assistant system prompt shared by every session. Kept short
/// because Gemma 3n context is precious and emergency answers must stay
/// terse and actionable.
const String _aegisSystemPrompt = '''
You are Aegis, an offline emergency assistant. The user may be injured, in
danger, or trying to help someone who is. Follow these rules on every turn:

1. If the situation is life-threatening, tell the user to call emergency
   services immediately.
2. Answer in plain language, one step at a time, short sentences. Prefer
   numbered steps when giving first-aid instructions.
3. Never invent locations, phone numbers, or medical facts. If you do not
   know, say so and suggest calling emergency services.
4. Reply in the same language the user spoke.
5. Keep responses under 120 words unless the user explicitly asks for more.
''';

/// Wraps flutter_gemma's modern API so the rest of the app can treat the
/// LLM as a simple text-in/text-out service.
///
/// Lifecycle:
///   setPack(pack) → install the pack with flutter_gemma (uses the file
///     we already downloaded) → getActiveModel → cache one model AND
///     one [InferenceModelSession]. Subsequent ask()/askStream() calls
///     reuse the same session.
///
/// **Why we cache the session.** Internally, every flutter_gemma session
/// constructs a fresh LiteRT-LM `Conversation` and prefills the system
/// instruction. Our `_aegisSystemPrompt` is ~150 tokens, which on a
/// mid-tier Android device adds 1–3 s of latency to the *very first
/// token* of every reply if we recreate the session per turn. Google's
/// own AI Edge Gallery sample does what we now do: build the
/// conversation once and call `sendMessage` on it for every user turn —
/// see `LlmChatModelHelper.kt`. The session-reuse model means turn N+1
/// starts decoding immediately because the system prompt is already
/// cached in the KV-store.
///
/// **Conversation history.** Reusing the session means the model sees
/// prior turns. That is intentional and matches the Gallery: a panicked
/// user re-asking the same question benefits from continuity. Use
/// [resetSession] when starting a *new* top-level conversation so old
/// context doesn't bleed in.
class LlmService {
  LlmService(this._registry);

  final ModelRegistry _registry;

  VoiceModelPack? _pack;
  InferenceModel? _model;
  InferenceModelSession? _session;
  bool _installed = false;
  Future<void>? _loadFuture;

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

  /// True if the currently-bound pack is installed on disk.
  Future<bool> isAvailable() async {
    final pack = _pack;
    if (pack == null) return false;
    return _registry.isInstalled(pack);
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

  Future<String> _askOnce(String userText, {required int maxTokens}) async {
    final session = await _ensureSession(maxTokens: maxTokens);
    try {
      await session.addQueryChunk(Message.text(text: userText, isUser: true));
      final raw = await session.getResponse();
      return _sanitizeFinalResponse(raw);
    } on Object {
      // The session may be in an inconsistent state after a generation
      // failure. Drop it so the next call rebuilds a clean conversation
      // (and so the OpenCL → CPU fallback in [_shouldFallbackToCpu] picks
      // up a fresh session on the new backend).
      await _disposeSession();
      rethrow;
    }
    // NB: the session is intentionally NOT closed here. We reuse the
    // same conversation across turns so the system prompt only prefills
    // once — see the class docstring for why.
  }

  Stream<String> _askStreamOnce(
    String userText, {
    required int maxTokens,
  }) async* {
    final session = await _ensureSession(maxTokens: maxTokens);
    try {
      await session.addQueryChunk(Message.text(text: userText, isUser: true));
      yield* _sanitizeStream(session.getResponseAsync());
    } on Object {
      await _disposeSession();
      rethrow;
    }
  }

  /// Lazily build (or return the cached) session for the active model.
  /// Sampling params and the system prompt are baked in at session-
  /// creation time — keep them fixed across the app, otherwise we'd lose
  /// the prefill cache benefit.
  Future<InferenceModelSession> _ensureSession({required int maxTokens}) async {
    final cached = _session;
    if (cached != null) return cached;
    final model = await _ensureModel(maxTokens: maxTokens);
    final session = await model.createSession(
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
      // Thinking OFF for time-to-first-token. With `enableThinking: true`
      // Gemma 4 IT decodes a full `<|channel>thought\n...<channel|>`
      // reasoning chain *before* the user-visible reply — measured at
      // 10-40s on-device, which is unusable for an emergency TTS loop.
      // We trade internal reasoning for response speed and rely on the
      // system prompt's "answer one step at a time, prefer numbered
      // steps" instruction to give the user *externally* structured
      // guidance instead. The thinking-block scrubber stays in place as
      // a belt-and-suspenders safety net in case the model emits a
      // thought header anyway (the SDK's docs warn that the
      // `enableThinking` flag is "not reliable for all model bundles").
      // Gallery's `BooleanSwitchConfig(key = ENABLE_THINKING,
      // defaultValue = false)` agrees with this tradeoff.
      enableThinking: false,
      systemInstruction: _aegisSystemPrompt,
    );
    _session = session;
    return session;
  }

  /// Close the cached session and clear conversation history. The next
  /// [ask] / [askStream] will lazily build a fresh one. Use this between
  /// distinct user conversations so context from a prior emergency does
  /// not leak into a new one.
  Future<void> resetSession() => _disposeSession();

  Future<void> _disposeSession() async {
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.close();
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
  String _sanitizeFinalResponse(String response) {
    final withoutThinking = response.replaceAll(_thinkBlockRegex, '');
    return withoutThinking.replaceAll(_reservedToken, '').trim();
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
  Stream<String> _sanitizeStream(Stream<String> tokens) async* {
    var buffer = '';
    var inThinking = false;

    String stripReserved(String text) => text.replaceAll(_reservedToken, '');

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
            if (safe.isNotEmpty) yield safe;
            buffer = buffer.substring(startIdx + _thinkStart.length);
            inThinking = true;
          } else {
            final partial = partialSuffix(buffer, _thinkStart);
            final safe = stripReserved(
              buffer.substring(0, buffer.length - partial),
            );
            if (safe.isNotEmpty) yield safe;
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
      if (tail.isNotEmpty) yield tail;
    }
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
      await _install(pack);
      await _disposeModel();
      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: _preferredBackend,
      );
      _model = model;
      completer.complete();
      return model;
    } on Object catch (e, st) {
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
    // Sessions hold a native handle into the model — close them first so
    // the LiteRT-LM Conversation is gone before the Engine is.
    await _disposeSession();
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
