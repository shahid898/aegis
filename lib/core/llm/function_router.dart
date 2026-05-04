import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/tool.dart';

import '../alert/alert_event.dart';
import '../sms_classifier/classification.dart';
import '../voice/llm_service.dart';
import '../voice/model_pack.dart';
import 'function_call.dart';
import 'function_call_parser.dart';

/// Wraps a [LlmService] so the rest of the app can ask "given this alert,
/// what should I do?" and receive a list of [FunctionCall]s.
///
/// FunctionGemma 270M is the canonical model for this role — a small
/// (~270 MB Q8) Gemma checkpoint finetuned by litert-community for mobile
/// function calling. We register the pack with [LlmService] once and ask
/// the service to flip into the router role before every [route] call so
/// the user-facing chat brain (Gemma 4 IT) and the router brain don't
/// fight over the single flutter_gemma engine.
///
/// Routing is best-effort: if the router pack isn't downloaded yet, or
/// the LLM throws, the function returns an empty plan and the
/// [AlertRouter] falls back to its regex-based dispatch path. The siren
/// can never be silenced by an LLM failure.
class FunctionRouter {
  FunctionRouter({
    required LlmService llm,
    required VoiceModelPack routerPack,
    FunctionCallParser? parser,
    List<FunctionDefinition> definitions = defaultFunctionDefinitions,
    // flutter_gemma treats `maxTokens` as the **total** KV-cache budget
    // (prompt + output), not an output cap. FunctionGemma 270M ships
    // with a 1024-token cache (see filename
    // `mobile_actions_q8_ekv1024.litertlm`), so we size to match. The
    // compact prompt produced by [_buildSystemPrompt] runs ~250 tokens,
    // leaving ~700 tokens for the alert body + function-call output.
    int maxTokens = 1024,
  })  : _llm = llm,
        _routerPack = routerPack,
        _parser = parser ?? FunctionCallParser(allowList: definitions),
        _definitions = definitions,
        _maxTokens = maxTokens;

  final LlmService _llm;
  final VoiceModelPack _routerPack;
  final FunctionCallParser _parser;
  final List<FunctionDefinition> _definitions;
  final int _maxTokens;

  /// Ask the model how to react to [event] given the regex first-pass
  /// [classification]. Returns the list of parsed [FunctionCall]s in the
  /// order the model emitted them. An empty list means "model declined" —
  /// callers should fall back to dispatching the alarm based purely on
  /// the regex classifier.
  ///
  /// Never throws on parse failures: a misbehaving on-device model must
  /// not be able to silence Aegis. Network-level / model-load failures
  /// still bubble up so the caller can decide whether to retry.
  Future<List<FunctionCall>> route({
    required AlertEvent event,
    required AlertClassification classification,
    String? preferredLanguage,
  }) async {
    // Make sure the LLM service knows about our router pack and is
    // currently in the router role before we issue the one-shot. This
    // is idempotent — if the router pack is already active and
    // registered the swap is a no-op.
    _llm.setRouterPack(_routerPack);
    _llm.useRouter();

    // Gate on whether the *router* pack is on disk, not whether the
    // currently-loaded model happens to be installed. Without this
    // check the LlmService would throw a "pack is not installed" error
    // mid-flight; instead we cleanly fall back to the regex path.
    if (!await _llm.isPackAvailable(_routerPack)) {
      if (kDebugMode) {
        debugPrint(
          '[FunctionRouter] router pack ${_routerPack.id} not installed, '
          'returning empty plan (regex fallback will fire if needed)',
        );
      }
      return const [];
    }

    final routingTools = _routingDefinitions;
    final systemInstruction = _buildSystemInstruction(preferredLanguage);
    final userPrompt = _buildUserPrompt(event, classification);
    final first = await _runWithTools(
      userPrompt: userPrompt,
      systemInstruction: systemInstruction,
      definitions: routingTools,
      toolChoice: ToolChoice.auto,
    );
    if (first.calls.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[FunctionRouter] parsed ${first.calls.length} call(s) from '
          '${first.sourceLength} chars',
        );
      }
      return first.calls;
    }

    final repairPrompt = _buildRepairPrompt(
      userPrompt: userPrompt,
      previousResponse: first.rawText,
    );
    final second = await _runWithTools(
      userPrompt: repairPrompt,
      systemInstruction: systemInstruction,
      definitions: routingTools,
      toolChoice: ToolChoice.required,
    );
    if (kDebugMode) {
      debugPrint(
        '[FunctionRouter] parsed ${second.calls.length} call(s) from '
        '${second.sourceLength} chars (repair pass)',
      );
    }
    return second.calls;
  }

  Future<_RouteParseResult> _runWithTools({
    required String userPrompt,
    required String systemInstruction,
    required List<FunctionDefinition> definitions,
    required ToolChoice toolChoice,
  }) async {
    final response = await _llm.oneShotWithTools(
      userPrompt: userPrompt,
      tools: definitions
          .map(
            (d) => Tool(
              name: d.action.wireName,
              description: d.description,
              parameters: d.parameters,
            ),
          )
          .toList(growable: false),
      systemInstruction: systemInstruction,
      toolChoice: toolChoice,
      maxTokens: _maxTokens,
      // Routing is a structured task — keep the sampler tight so we
      // hit the function-call protocol consistently. Chat answers use
      // the loose 1.0/64/0.95 set for a more conversational tone.
      temperature: 0.2,
      topK: 40,
      topP: 0.9,
    );

    return switch (response) {
      FunctionCallResponse() => _fromFunctionCalls([response], definitions),
      ParallelFunctionCallResponse() => _fromFunctionCalls(
        response.calls,
        definitions,
      ),
      TextResponse() => _parseTextResponse(response.token),
      ThinkingResponse() => _parseTextResponse(response.content),
    };
  }

  _RouteParseResult _parseTextResponse(String raw) {
    if (kDebugMode) {
      debugPrint(
        '[FunctionRouter] raw LLM response (${raw.length} chars):\n'
        '---START---\n$raw\n---END---',
      );
    }
    return _RouteParseResult(calls: _parser.parse(raw), rawText: raw);
  }

  _RouteParseResult _fromFunctionCalls(
    List<FunctionCallResponse> responses,
    List<FunctionDefinition> definitions,
  ) {
    final out = <FunctionCall>[];
    final allowed = definitions.map((d) => d.action).toSet();
    for (final r in responses) {
      final action = FunctionRouteAction.fromWire(r.name);
      if (action == null || !allowed.contains(action)) continue;
      out.add(
        FunctionCall(
          action: action,
          arguments: Map<String, dynamic>.from(r.args),
          rationale: null,
        ),
      );
    }
    if (kDebugMode) {
      debugPrint(
        '[FunctionRouter] structured function response count=${out.length}',
      );
    }
    return _RouteParseResult(
      calls: List.unmodifiable(out),
      rawText: responses
          .map((r) => '${r.name}(${r.args.entries.map((e) => '${e.key}=${e.value}').join(',')})')
          .join(';'),
    );
  }

  List<FunctionDefinition> get _routingDefinitions {
    const allowed = <FunctionRouteAction>{
      FunctionRouteAction.dispatchLocalAlarm,
      FunctionRouteAction.requestClarification,
    };
    return _definitions
        .where((d) => allowed.contains(d.action))
        .toList(growable: false);
  }

  String _buildRepairPrompt({
    required String userPrompt,
    required String previousResponse,
  }) {
    return '''
$userPrompt

Your previous answer was invalid for tool calling:
"""
$previousResponse
"""

Decide classification again from the message:
- REAL life-safety emergency (imminent risk to life/safety) => MUST call dispatch_local_alarm.
- NOT a real emergency (drill/test, promo/spam, OTP, social, "sale", opt-out text) => MUST call request_clarification.

Return exactly ONE valid function call from this allowed set only:
- dispatch_local_alarm
- request_clarification

No prose. No explanation. No markdown. No other function names.
''';
  }

  String _buildSystemInstruction(String? language) {
    final languageRule = (language == null || language.isEmpty)
        ? 'reply in the alert\'s language'
        : 'reply in "$language"';
    // Keep this short: tool declarations are injected natively by
    // flutter_gemma's chat path when `tools` are passed.
    return '''
You route inbound text messages for emergency triage.

- REAL emergency = imminent threat to life or safety (disaster, evacuation, civil emergency, child abduction, hazmat, terror, mass-casualty event, etc.).
- NOT a real emergency = marketing/spam, bills, OTPs, social messages, "EMERGENCY SALE", clickbait, anything that just uses urgent words.

Rules:
- If REAL emergency: emit dispatch_local_alarm FIRST (severity = your call: critical|high|medium|low), then any other useful actions.
- If NOT a real emergency: emit request_clarification only, or no calls at all. Do NOT emit dispatch_local_alarm.
- Most time-sensitive action first.
- $languageRule.
Respond using tool calls only.''';
  }

  String _buildUserPrompt(
    AlertEvent event,
    AlertClassification classification,
  ) {
    // No regex hints — the model judges purely on the raw body + sender.
    // [classification] is intentionally unused; it's still in the
    // signature so the call site doesn't need to change while we
    // migrate. See `SmsClassifier`'s file doc for the rationale.
    final sender = event.sender ?? 'unknown';
    final source = event.source.name;

    return '''
INBOUND MESSAGE
source: $source
sender: $sender

BODY:
"""
${event.body}
"""

Decide whether this is a REAL life-safety emergency and call the best tool(s).
''';
  }
}

class _RouteParseResult {
  const _RouteParseResult({required this.calls, required this.rawText});

  final List<FunctionCall> calls;
  final String rawText;
  int get sourceLength => rawText.length;
}
