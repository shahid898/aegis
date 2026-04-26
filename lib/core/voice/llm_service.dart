import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'model_pack.dart';
import 'model_registry.dart';

/// Reserved Gemma vocabulary placeholders (e.g. `<unused3>`) leak through
/// when the LiteRT-LM chat template doesn't perfectly line up with what the
/// weights were trained against. They are never meaningful output, so we
/// strip them in both the streaming and non-streaming paths.
final RegExp _unusedToken = RegExp(r'<unused\d+>');

/// Gemma 4 IT chain-of-thought delimiters. We turn `enableThinking: true`
/// on at the session because letting the model reason internally produces
/// better multi-step emergency advice — but we don't surface that scratchpad
/// to the user. Everything between these markers is dropped by the
/// streaming filter, leaving only the actual reply.
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
/// Model lifecycle:
///   setPack(pack) → install the pack with flutter_gemma (uses the file
///     we already downloaded) → getActiveModel → cache one session.
///   Subsequent ask()/askStream() calls reuse the same session.
///
/// Sessions are rebuilt between turns so the model forgets previous
/// conversation — emergency guidance is stateless. This keeps token
/// usage low and avoids accidental hallucinated context carryover.
class LlmService {
  LlmService(this._registry);

  final ModelRegistry _registry;

  VoiceModelPack? _pack;
  InferenceModel? _model;
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
    final model = await _ensureModel(maxTokens: maxTokens);
    final session = await model.createSession(
      // Gemma's published defaults — temp=0.7 + topK=40 was making the
      // model collapse onto repeated `<unused3>` tokens because the
      // truncated probability mass left no escape from a degenerate loop.
      // 1.0 / 64 / 0.95 is what HuggingFace's tokenizer_config recommends
      // for Gemma instruction-tuned variants and matches the template the
      // weights were trained against.
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
      // Let Gemma 4 IT reason internally — better answers on multi-step
      // emergency advice. The thinking block is wrapped in
      // `<|channel>thought\n...<channel|>` and stripped by `_sanitizeStream`
      // / `_sanitizeFinalResponse` before the user ever sees it, so flipping
      // this on costs only inference time, not UX clarity.
      enableThinking: true,
      systemInstruction: _aegisSystemPrompt,
    );
    try {
      await session.addQueryChunk(Message.text(text: userText, isUser: true));
      final raw = await session.getResponse();
      return _sanitizeFinalResponse(raw);
    } finally {
      await session.close();
    }
  }

  Stream<String> _askStreamOnce(
    String userText, {
    required int maxTokens,
  }) async* {
    final model = await _ensureModel(maxTokens: maxTokens);
    final session = await model.createSession(
      // Gemma's published defaults — temp=0.7 + topK=40 was making the
      // model collapse onto repeated `<unused3>` tokens because the
      // truncated probability mass left no escape from a degenerate loop.
      // 1.0 / 64 / 0.95 is what HuggingFace's tokenizer_config recommends
      // for Gemma instruction-tuned variants and matches the template the
      // weights were trained against.
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
      // Let Gemma 4 IT reason internally — better answers on multi-step
      // emergency advice. The thinking block is wrapped in
      // `<|channel>thought\n...<channel|>` and stripped by `_sanitizeStream`
      // / `_sanitizeFinalResponse` before the user ever sees it, so flipping
      // this on costs only inference time, not UX clarity.
      enableThinking: true,
      systemInstruction: _aegisSystemPrompt,
    );
    try {
      await session.addQueryChunk(Message.text(text: userText, isUser: true));
      yield* _sanitizeStream(session.getResponseAsync());
    } finally {
      await session.close();
    }
  }

  /// Removes thinking blocks and reserved placeholder tokens from a fully
  /// accumulated response. Mirrors flutter_gemma's
  /// `ModelThinkingFilter.removeThinkingFromText` for `ModelType.gemmaIt`,
  /// plus a `<unused\d+>` strip for residual reserved-vocab leaks.
  String _sanitizeFinalResponse(String response) {
    final withoutThinking = response.replaceAll(_thinkBlockRegex, '');
    return withoutThinking.replaceAll(_unusedToken, '').trim();
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

    String stripUnused(String text) => text.replaceAll(_unusedToken, '');

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
            final safe = stripUnused(buffer.substring(0, startIdx));
            if (safe.isNotEmpty) yield safe;
            buffer = buffer.substring(startIdx + _thinkStart.length);
            inThinking = true;
          } else {
            final partial = partialSuffix(buffer, _thinkStart);
            final safe = stripUnused(
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
      final tail = stripUnused(buffer);
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
