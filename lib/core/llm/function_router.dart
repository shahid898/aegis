import 'package:flutter/foundation.dart';

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

    final systemInstruction = _buildSystemPrompt(preferredLanguage);
    final userPrompt = _buildUserPrompt(event, classification);

    String raw;
    try {
      raw = await _llm.oneShot(
        systemInstruction: systemInstruction,
        userPrompt: userPrompt,
        maxTokens: _maxTokens,
        // Routing is a structured task — keep the sampler tight so we
        // hit the function-call protocol consistently. Chat answers use
        // the loose 1.0/64/0.95 set for a more conversational tone.
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
      );
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[FunctionRouter] LLM call failed: $e\n$st');
      }
      return const [];
    }

    final calls = _parser.parse(raw);
    if (kDebugMode) {
      debugPrint(
        '[FunctionRouter] parsed ${calls.length} call(s) from '
        '${raw.length} chars',
      );
    }
    return calls;
  }

  String _buildSystemPrompt(String? language) {
    final languageRule = (language == null || language.isEmpty)
        ? 'reply in the alert\'s language'
        : 'reply in "$language"';
    final tools = _definitions.map(_compactToolLine).join('\n');
    // Terse on purpose: every line of prose costs prefill tokens, and
    // FunctionGemma's KV cache is 1024 total. See class doc.
    //
    // No regex first-pass any more — *you* (the model) are the sole
    // judge of whether the message is a real life-safety emergency.
    return '''
You route inbound text messages. You are the SOLE judge of whether the message is a real life-safety emergency.

Decide first:
- REAL emergency = imminent threat to life or safety (disaster, evacuation, civil emergency, child abduction, hazmat, terror, mass-casualty event, etc.).
- NOT a real emergency = marketing/spam, bills, OTPs, social messages, "EMERGENCY SALE", clickbait, anything that just uses urgent words.

Output ONLY function-call blocks, no prose:
<start_function_call>
{"name":"<name>","arguments":{...},"rationale":"<short>"}
<end_function_call>

Rules:
- If REAL emergency: emit dispatch_local_alarm FIRST (severity = your call: critical|high|medium|low), then any other useful actions.
- If NOT a real emergency: emit request_clarification only, or no calls at all. Do NOT emit dispatch_local_alarm.
- Most time-sensitive action first.
- $languageRule.

Catalog:
$tools''';
  }

  /// One-line tool description: `name(arg1, arg2, [opt]) — what it does.`
  /// Drops the JSON-schema wrapper (~3-4× cheaper in tokens than
  /// `JsonEncoder.withIndent` on the same definition).
  String _compactToolLine(FunctionDefinition def) {
    final params = def.parameters['properties'] as Map<String, dynamic>? ?? {};
    final required = (def.parameters['required'] as List?)?.cast<String>() ??
        const <String>[];
    final argFragments = <String>[];
    for (final entry in params.entries) {
      final name = entry.key;
      final spec = entry.value as Map<String, dynamic>? ?? const {};
      final type = spec['type'] as String? ?? 'string';
      final enumValues = (spec['enum'] as List?)?.cast<String>();
      final typeHint =
          enumValues != null ? enumValues.join('|') : type;
      final fragment = '$name:$typeHint';
      argFragments.add(required.contains(name) ? fragment : '[$fragment]');
    }
    final args = argFragments.join(', ');
    // Collapse the description to its first sentence to keep things tight.
    final firstSentence = def.description.split('.').first.trim();
    return '- ${def.action.wireName}($args) — $firstSentence.';
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

Decide if this is a REAL life-safety emergency, then emit the function-call blocks.
''';
  }
}
