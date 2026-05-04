import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// LLM as a simple text-in/text-out service.
///
/// Lifecycle:
///   setPack(pack) → install the pack with flutter_gemma (uses the file
///     we already downloaded) → getActiveModel → cache one model AND
///     one [InferenceChat]. Subsequent ask()/askStream() calls reuse the
///     same chat object (and therefore the same underlying conversation).
///
/// **Why we use [InferenceChat] instead of raw [InferenceModelSession].**
/// flutter_gemma exposes two APIs for multi-turn conversations:
///
///   * `model.createSession()` — one underlying LiteRT-LM `Conversation`
///     reused per `addQueryChunk` + `getResponseAsync`. In theory the
///     `Conversation` retains history natively; in practice we observed
///     turn N+1 sometimes losing context from turn N (and `Conversation`
///     exposes no replay API). It's the right primitive for one-shot
///     prompts but not for chat.
///   * `model.createChat()` — wraps a session with explicit history
///     tracking on the Dart side (`_modelHistory`). When the cumulative
///     token count approaches the model's context window, the chat
///     transparently recreates the session and replays the saved
///     messages, preserving the conversation across the boundary. This
///     is the path the flutter_gemma example app and integration tests
///     all take.
///
/// **Speed.** Both APIs share the same prefill-cache benefit: the system
/// instruction is baked into the underlying session at creation time, so
/// after the first turn the ~150-token `_aegisSystemPrompt` is already
/// in the KV-store. Caching the [InferenceChat] across turns therefore
/// gives us *both* fast time-to-first-token *and* correct multi-turn
/// memory. Google's AI Edge Gallery uses the equivalent native pattern
/// (one `Conversation` per chat instance, reused for every user turn).
///
/// **Conversation history.** Reusing the chat means the model sees
/// prior turns within a conversation — exactly what a panicked user
/// re-asking the same question needs. Call [resetSession] (kept under
/// that name for backward compatibility) when starting a *new*
/// top-level conversation so old context doesn't bleed in.
class LlmService {
  LlmService(this._registry);

  final ModelRegistry _registry;

  // The two roles. flutter_gemma 0.13.6 only allows one model loaded at a
  // time, so the chat brain (Gemma 4 IT, ~2.5 GB) and the routing brain
  // (FunctionGemma 270M, ~270 MB) are registered separately and the active
  // one is hot-swapped via [useChat] / [useRouter].
  VoiceModelPack? _chatPack;
  VoiceModelPack? _routerPack;

  // The pack the engine is currently loaded against (or about to be — set
  // synchronously by [_activate], the heavy load happens lazily on the
  // next [_ensureModel] call). When this is null, no role has been picked
  // yet and [ask]/[oneShot] will throw.
  VoiceModelPack? _activePack;

  InferenceModel? _model;
  InferenceChat? _chat;
  bool _installed = false;
  Future<void>? _loadFuture;
  String? _preferredLanguage;
  Future<void> _oneShotChain = Future<void>.value();

  /// The backend we'll try next time we (re)load the model. We start on GPU
  /// because real Adreno/Mali phones can run the WebGPU executor + OpenCL
  /// TopK sampler at full speed; we drop to CPU permanently for the rest of
  /// this process if a generation throws "Can not find OpenCL library on
  /// this device" — the emulator and OpenCL-less devices fall into that bucket.
  PreferredBackend _preferredBackend = PreferredBackend.gpu;

  /// The pack the engine is currently loaded against (or about to be on
  /// the next [ask]/[oneShot] call). Null until [setChatPack] /
  /// [setRouterPack] / [setPack] has been called for either role.
  VoiceModelPack? get pack => _activePack;

  /// Convenience accessors for callers that need to query a specific role.
  VoiceModelPack? get chatPack => _chatPack;
  VoiceModelPack? get routerPack => _routerPack;

  bool get isReady => _model != null;

  /// Register the chat-role pack (typically the user-facing assistant
  /// brain — Gemma 4 IT). Does not load the model nor activate the role —
  /// call [useChat] (or the legacy [setPack]) to make this pack the active
  /// one. Idempotent for repeated calls with the same pack id.
  void setChatPack(VoiceModelPack pack) {
    if (pack.kind != ModelKind.llm) {
      throw ArgumentError('LlmService.setChatPack requires an LLM pack');
    }
    if (_chatPack?.id == pack.id) return;
    _chatPack = pack;
    // If the chat pack is currently active, swapping its identity means
    // the engine needs reloading — drop everything cached.
    if (_activePack?.id != pack.id && _activePack == _chatPack) {
      _activate(pack);
    }
  }

  /// Register the router-role pack (typically FunctionGemma 270M, a small
  /// model finetuned for function calling). Does not load nor activate
  /// the role — [useRouter] flips the active pack.
  void setRouterPack(VoiceModelPack pack) {
    if (pack.kind != ModelKind.llm) {
      throw ArgumentError('LlmService.setRouterPack requires an LLM pack');
    }
    if (_routerPack?.id == pack.id) return;
    _routerPack = pack;
  }

  /// Backward-compatible alias used by the chat surface (assistant cubit):
  /// register [pack] as the chat brain AND activate it so the next
  /// [ask] / [askStream] call loads it.
  void setPack(VoiceModelPack pack) {
    setChatPack(pack);
    useChat();
  }

  /// Make the chat-role pack the active engine. No-op if it's already
  /// active. The expensive engine reload happens lazily on the next
  /// [ask] / [askStream] / [oneShot] call.
  void useChat() => _activate(_chatPack);

  /// Make the router-role pack the active engine. No-op if it's already
  /// active. Used by [FunctionRouter] before [oneShot] so the LLM call
  /// runs against FunctionGemma rather than the chat brain.
  void useRouter() => _activate(_routerPack);

  /// Synchronous role swap: replace [_activePack] and tear down anything
  /// loaded against the old pack. Heavy work (download check + native
  /// load) is deferred to the next [_ensureModel] call.
  void _activate(VoiceModelPack? pack) {
    if (pack == null) return;
    if (_activePack?.id == pack.id) return;
    _activePack = pack;
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

  /// True if the currently-active pack is installed on disk.
  Future<bool> isAvailable() async {
    final pack = _activePack;
    if (pack == null) return false;
    return _registry.isInstalled(pack);
  }

  /// True if [pack] is installed on disk, regardless of which role is
  /// currently active. The router uses this to gate routing on whether
  /// the FunctionGemma pack is downloaded — if the router pack isn't
  /// there yet, it returns an empty plan and the regex fallback fires.
  Future<bool> isPackAvailable(VoiceModelPack pack) =>
      _registry.isInstalled(pack);

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

  /// Run a single, history-free prompt. The model is shared with [ask] /
  /// [askStream] (LiteRT-LM only allows one engine in process), but the
  /// underlying [InferenceModelSession] is built fresh and torn down at
  /// the end of the call so nothing this method emits leaks into the
  /// user-visible chat conversation. This is what the FunctionGemma
  /// router uses to ask "given this alert, what should I do?" without
  /// polluting the multi-turn dialogue Aegis is having with the user.
  ///
  /// [systemInstruction] is prepended to the prompt verbatim — pass an
  /// empty string if you want raw user-only input.
  Future<String> oneShot({
    required String systemInstruction,
    required String userPrompt,
    int maxTokens = 1024,
    double temperature = 0.2,
    int topK = 40,
    double topP = 0.95,
  }) {
    final completer = Completer<String>();
    _oneShotChain = _oneShotChain
        .catchError((Object error, StackTrace stackTrace) {
          // Keep the chain alive after failures; otherwise one failed call
          // can permanently block every later oneShot() waiter.
        })
        .then((_) async {
      try {
        final output = await _oneShotWithFallback(
          systemInstruction: systemInstruction,
          userPrompt: userPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
          topK: topK,
          topP: topP,
        );
        completer.complete(output);
      } on Object catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// One-shot router call using flutter_gemma's chat API with tool metadata.
  /// This keeps tool declarations in the model-facing conversation state
  /// instead of relying only on prompt text instructions.
  Future<ModelResponse> oneShotWithTools({
    required String userPrompt,
    required List<Tool> tools,
    String? systemInstruction,
    ToolChoice toolChoice = ToolChoice.required,
    int maxTokens = 1024,
    double temperature = 0.2,
    int topK = 40,
    double topP = 0.95,
  }) {
    final completer = Completer<ModelResponse>();
    _oneShotChain = _oneShotChain
        .catchError((Object error, StackTrace stackTrace) {
          // Keep the chain alive after failures; otherwise one failed call
          // can permanently block every later oneShot() waiter.
        })
        .then((_) async {
          try {
            final output = await _oneShotWithToolsWithFallback(
              userPrompt: userPrompt,
              tools: tools,
              systemInstruction: systemInstruction,
              toolChoice: toolChoice,
              maxTokens: maxTokens,
              temperature: temperature,
              topK: topK,
              topP: topP,
            );
            completer.complete(output);
          } on Object catch (e, st) {
            completer.completeError(e, st);
          }
        });
    return completer.future;
  }

  Future<String> _oneShotWithFallback({
    required String systemInstruction,
    required String userPrompt,
    required int maxTokens,
    required double temperature,
    required int topK,
    required double topP,
  }) async {
    try {
      return await _oneShotOnce(
        systemInstruction: systemInstruction,
        userPrompt: userPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topK: topK,
        topP: topP,
      );
    } on Object catch (e) {
      if (!await _shouldFallbackToCpu(e)) rethrow;
      return _oneShotOnce(
        systemInstruction: systemInstruction,
        userPrompt: userPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topK: topK,
        topP: topP,
      );
    }
  }

  Future<ModelResponse> _oneShotWithToolsWithFallback({
    required String userPrompt,
    required List<Tool> tools,
    required String? systemInstruction,
    required ToolChoice toolChoice,
    required int maxTokens,
    required double temperature,
    required int topK,
    required double topP,
  }) async {
    try {
      return await _oneShotWithToolsOnce(
        userPrompt: userPrompt,
        tools: tools,
        systemInstruction: systemInstruction,
        toolChoice: toolChoice,
        maxTokens: maxTokens,
        temperature: temperature,
        topK: topK,
        topP: topP,
      );
    } on Object catch (e) {
      if (!await _shouldFallbackToCpu(e)) rethrow;
      return _oneShotWithToolsOnce(
        userPrompt: userPrompt,
        tools: tools,
        systemInstruction: systemInstruction,
        toolChoice: toolChoice,
        maxTokens: maxTokens,
        temperature: temperature,
        topK: topK,
        topP: topP,
      );
    }
  }

  Future<String> _oneShotOnce({
    required String systemInstruction,
    required String userPrompt,
    required int maxTokens,
    required double temperature,
    required int topK,
    required double topP,
  }) async {
    final model = await _ensureModel(maxTokens: maxTokens);
    final trimmedSystem = systemInstruction.trim();
    final session = await model.createSession(
      temperature: temperature,
      topK: topK,
      topP: topP,
      systemInstruction: trimmedSystem.isEmpty ? null : trimmedSystem,
    );
    try {
      await session.addQueryChunk(Message.text(text: userPrompt, isUser: true));
      final raw = await session.getResponse();
      return _sanitizeFinalResponse(raw);
    } finally {
      try {
        await session.close();
      } on Object {
        // best-effort — the underlying Conversation may already be gone.
      }
    }
  }

  Future<ModelResponse> _oneShotWithToolsOnce({
    required String userPrompt,
    required List<Tool> tools,
    required String? systemInstruction,
    required ToolChoice toolChoice,
    required int maxTokens,
    required double temperature,
    required int topK,
    required double topP,
  }) async {
    final model = await _ensureModel(maxTokens: maxTokens);
    final chat = await model.createChat(
      temperature: temperature,
      topK: topK,
      topP: topP,
      modelType: ModelType.functionGemma,
      supportsFunctionCalls: true,
      toolChoice: toolChoice,
      tools: tools,
      systemInstruction: systemInstruction,
    );
    try {
      await chat.addQueryChunk(Message.text(text: userPrompt, isUser: true));
      return await chat.generateChatResponse();
    } finally {
      try {
        await chat.close();
      } on Object {
        // best-effort
      }
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
    final chat = await _ensureChat(maxTokens: maxTokens);
    _logHistorySnapshot(chat, label: 'ask', incoming: userText);
    try {
      await chat.addQueryChunk(Message.text(text: userText, isUser: true));
      final response = await chat.generateChatResponse();
      final raw = response is TextResponse ? response.token : '';
      return _sanitizeFinalResponse(raw);
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
    try {
      await chat.addQueryChunk(Message.text(text: userText, isUser: true));
      yield* _sanitizeStream(
        chat
            .generateChatResponseAsync()
            .where((r) => r is TextResponse)
            .map((r) => (r as TextResponse).token)
            .where((t) => t.isNotEmpty),
      );
    } on Object {
      await _disposeChat();
      rethrow;
    }
  }

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
      isThinking: false,
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

  /// Force the active model to load and run a single throw-away inference
  /// so the LiteRT-LM engine, GPU shaders, and KV-cache prefill are paid
  /// for *now* rather than on the first real alert.
  ///
  /// Cold-start of FunctionGemma 270M on a GPU device is dominated by
  /// shader compile + KV warm-up — measured at 25–40 s on real hardware.
  /// The AlertRouter's per-alert watchdog can't realistically budget for
  /// that, so we burn the cost up-front (e.g. from `configureDependencies`
  /// at boot) and treat any failure as non-fatal: the router will still
  /// retry on the next alert, just on a cold engine.
  ///
  /// Caller is expected to have already pinned the desired role via
  /// [useChat] / [useRouter]. No-op if the active pack is missing or not
  /// yet installed on disk.
  ///
  /// **Why every sampling parameter is exposed.** flutter_gemma's
  /// LiteRT-LM engine bakes the FIRST session's sampling and budget
  /// settings into permanent engine-level ceilings (`max_top_k`,
  /// `max_tokens`, …). Subsequent sessions are silently clamped to
  /// those ceilings. We observed this twice in production:
  ///
  ///   1. Warming up with `maxTokens: 64` locked the engine at 64 and
  ///      the next router call with a 448-token prompt died at the
  ///      JNI boundary with `Input token ids are too long. Exceeding
  ///      the maximum number of tokens allowed: 448 >= 64`.
  ///   2. Warming up with `topK: 1` (greedy) locked `max_top_k` at 1.
  ///      The router asked for `topK: 40` but was silently clamped to
  ///      greedy, FunctionGemma 270M then decoded into a degenerate
  ///      region for ~20 seconds and returned an empty string —
  ///      `[FunctionRouter] parsed 0 call(s) from 0 chars`.
  ///
  /// The defaults here mirror the **router's** sampling
  /// ([FunctionRouter.route] uses `temperature: 0.2, topK: 40,
  /// topP: 0.9, maxTokens: 1024`) so the engine's ceilings are sized
  /// for the router's needs. Callers warming the chat brain should
  /// override these to the chat sampling params instead.
  Future<void> warmUp({
    int maxTokens = 1024,
    double temperature = 0.2,
    int topK = 40,
    double topP = 0.9,
  }) async {
    final pack = _activePack;
    if (pack == null) {
      if (kDebugMode) {
        debugPrint('[LlmService] warm-up skipped: no active pack');
      }
      return;
    }
    if (!await _registry.isInstalled(pack)) {
      if (kDebugMode) {
        debugPrint(
          '[LlmService] warm-up skipped: pack ${pack.id} not installed',
        );
      }
      return;
    }
    final stopwatch = Stopwatch()..start();
    try {
      // Warm-up should not spend tens of seconds decoding throw-away text,
      // because that can starve real alert routing behind [_oneShotChain].
      // We only prime engine/session creation here.
      final model = await _ensureModel(maxTokens: maxTokens);
      final session = await model.createSession(
        temperature: temperature,
        topK: topK,
        topP: topP,
        systemInstruction: null,
      );
      await session.close();
      if (kDebugMode) {
        debugPrint(
          '[LlmService] warm-up complete pack=${pack.id} '
          'took=${stopwatch.elapsedMilliseconds}ms',
        );
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[LlmService] warm-up failed (non-fatal) pack=${pack.id}: $e\n$st',
        );
      }
    }
  }

  /// Temporary diagnostic probe for FunctionGemma mobile-actions alignment.
  /// Sends a canonical training-style intent and logs raw model output.
  Future<void> runFunctionGemmaMobileActionProbe() async {
    const prompt = '''
Output ONLY function-call blocks, no prose, in native FunctionGemma format:
<start_function_call>
call:turn_on_flashlight{}
<end_function_call>

INBOUND MESSAGE
source: probe
sender: user

BODY:
"""
turn on the flashlight
"""
''';
    try {
      final raw = await oneShot(
        systemInstruction: '',
        userPrompt: prompt,
        maxTokens: 1024,
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
      );
      if (kDebugMode) {
        debugPrint(
          '[LlmService] FunctionGemma mobile-actions probe raw (${raw.length} chars):\n'
          '---START---\n$raw\n---END---',
        );
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[LlmService] FunctionGemma mobile-actions probe failed: $e\n$st',
        );
      }
    }
  }

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
    final pack = _activePack;
    if (pack == null) {
      throw StateError(
        'LlmService used before setChatPack/setRouterPack — call '
        'useChat()/useRouter() (or the legacy setPack) first',
      );
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
    final modelType =
        (_routerPack != null && pack.id == _routerPack!.id)
            ? ModelType.functionGemma
            : ModelType.gemmaIt;
    await FlutterGemma.installModel(
      modelType: modelType,
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
