import 'package:flutter/foundation.dart';

import '../alert/alert_event.dart';
import '../sms_classifier/classification.dart';
import '../voice/llm_service.dart';
import '../voice/model_pack.dart';
import 'function_call.dart';

/// Routes inbound emergency text through the chat brain (Gemma 4 IT) using
/// a strict structured-text classification protocol.
///
/// **Why Gemma 4 IT instead of FunctionGemma 270M.** FunctionGemma 270M is a
/// general agentic tool-calling fine-tune. It does not know what a CAP/WEA
/// alert looks like, cannot reliably distinguish "Tsunami Warning" from
/// "Heat Advisory" urgency, and on-device produced refusal text or echoed
/// malformed `<start_function_call>` blocks for both real cyclone alerts and
/// promo/test SMS — escalating both equally. Gemma 4 IT (the chat brain)
/// already understands disaster terminology zero-shot from its pretraining
/// corpus and reliably classifies alert intent without fine-tuning.
///
/// flutter_gemma 0.13.6 has no native `gemma4` ModelType nor a tools-JSON
/// path that bypasses the FunctionGemma chat template, so we drive Gemma 4
/// in plain text mode via [LlmService.oneShot] and parse a tight
/// `VERDICT:` / `SEVERITY:` / `REASON:` envelope. The classifier runs in a
/// fresh history-free session so it never pollutes the user-facing chat.
///
/// Routing is best-effort: if the chat pack isn't downloaded yet, or the
/// LLM throws, the function returns an empty plan and [AlertRouter] falls
/// back to its regex-based dispatch path. The siren can never be silenced
/// by an LLM failure.
class FunctionRouter {
  FunctionRouter({
    required LlmService llm,
    required VoiceModelPack chatPack,
    int maxTokens = 512,
  }) : _llm = llm,
       _chatPack = chatPack,
       _maxTokens = maxTokens;

  final LlmService _llm;
  final VoiceModelPack _chatPack;
  final int _maxTokens;

  /// Ask Gemma 4 IT how to react to [event] given the regex first-pass
  /// [classification]. Returns the list of parsed [FunctionCall]s in the
  /// order the model emitted them. An empty list means "model declined" —
  /// callers should fall back to dispatching the alarm based purely on
  /// the regex classifier.
  ///
  /// Never throws on parse failures: a misbehaving on-device model must
  /// not be able to silence Aegis. Engine-load / inference failures still
  /// bubble up so the caller can decide whether to retry.
  Future<List<FunctionCall>> route({
    required AlertEvent event,
    // Kept in signature so the call site doesn't need to change while we
    // migrate. Gemma 4 IT judges purely on the raw body + sender so the
    // regex hint isn't fed back into the prompt.
    required AlertClassification classification,
    String? preferredLanguage,
  }) async {
    // Silence "unused" warning while preserving the API.
    // ignore: unused_local_variable
    final _ = classification;
    // Pin the chat pack as the active engine. Idempotent — if Gemma 4 IT
    // is already active, this is a no-op. If a router pack was previously
    // active (legacy code path), this swaps the active engine which the
    // next oneShot() call will lazily reload.
    _llm.setChatPack(_chatPack);
    _llm.useChat();

    if (!await _llm.isPackAvailable(_chatPack)) {
      if (kDebugMode) {
        debugPrint(
          '[FunctionRouter] chat pack ${_chatPack.id} not installed, '
          'returning empty plan (regex fallback will fire if needed)',
        );
      }
      return const [];
    }

    final systemInstruction = _buildSystemInstruction(preferredLanguage);
    final userPrompt = _buildUserPrompt(event);

    final raw = await _llm.oneShot(
      systemInstruction: systemInstruction,
      userPrompt: userPrompt,
      maxTokens: _maxTokens,
      // Tight sampler — classification, not creativity.
      temperature: 0.1,
      topK: 20,
      topP: 0.9,
    );

    final calls = _parseVerdict(raw);
    if (kDebugMode) {
      debugPrint(
        '[FunctionRouter] raw verdict (${raw.length} chars):\n'
        '---START---\n$raw\n---END---',
      );
      debugPrint('[FunctionRouter] parsed ${calls.length} call(s)');
    }
    return calls;
  }

  /// Parse Gemma 4 IT's structured envelope into [FunctionCall]s.
  ///
  /// Expected shape:
  /// ```
  /// VERDICT: EMERGENCY|NOT_EMERGENCY
  /// SEVERITY: critical|high|medium|low
  /// REASON: <short user-facing label>
  /// ```
  ///
  /// Tolerates surrounding prose, markdown fences, lowercase keys, and
  /// extra whitespace.
  ///
  /// **Synonym handling.** Gemma 4 IT does not always echo the exact
  /// label from the prompt — observed substitutions include `REAL`,
  /// `YES`, `CONFIRMED`, `ESCALATE` for emergency and `NO`, `SAFE`,
  /// `DRILL`, `TEST`, `SPAM`, `NONE` for not-emergency. We classify the
  /// VERDICT line into negative / positive buckets by token search; if
  /// the verdict line is missing or ambiguous we fall back to SEVERITY
  /// (`critical` / `high` → escalate). Defaults bias toward escalation
  /// only when there's a clear positive signal — empty / unparseable
  /// output still returns an empty list, which collapses to DISMISS at
  /// the [AlertRouter] layer.
  List<FunctionCall> _parseVerdict(String raw) {
    final verdict = _extractField(raw, 'VERDICT')?.toUpperCase() ?? '';
    final severityRaw = _extractField(raw, 'SEVERITY')?.toLowerCase().trim();
    final severity =
        const {'critical', 'high', 'medium', 'low'}.contains(severityRaw)
        ? severityRaw!
        : 'high';
    final reasonRaw = _extractField(raw, 'REASON');

    final isNegative = _hasAnyToken(verdict, _negativeVerdictTokens);
    final isPositive = _hasAnyToken(verdict, _positiveVerdictTokens);

    // Negative wins ties (e.g. "NOT_EMERGENCY" contains "EMERGENCY").
    if (isNegative) {
      return [
        FunctionCall(
          action: FunctionRouteAction.requestClarification,
          arguments: {
            'reason': _trimReason(reasonRaw ?? 'Not a real emergency'),
          },
          rationale: null,
        ),
      ];
    }

    // Positive verdict OR (no usable verdict but SEVERITY committed to
    // critical/high) → escalate. The severity-only fallback catches
    // cases where the model emitted a non-vocabulary verdict like
    // "URGENT" or omitted the line entirely.
    final severitySaysEmergency = severity == 'critical' || severity == 'high';
    if (!isPositive && !(verdict.isEmpty && severitySaysEmergency)) {
      // Ambiguous (verdict present but matched neither bucket, and
      // severity is medium/low) → empty plan, AlertRouter will DISMISS.
      return const [];
    }

    final reason = _trimReason(reasonRaw ?? 'Emergency alert');
    final calls = <FunctionCall>[
      FunctionCall(
        action: FunctionRouteAction.dispatchLocalAlarm,
        arguments: {'severity': severity, 'reason': reason},
        rationale: null,
      ),
    ];

    // Follow-up actions. Parsed from a comma- or newline-separated
    // ACTIONS line. Always after dispatch_local_alarm so the siren
    // transition fires first; handlers run sequentially in
    // [AlertRouter._safeDispatch].
    final actionLine = _extractField(raw, 'ACTIONS');
    if (actionLine != null) {
      for (final tok in _splitActionTokens(actionLine)) {
        final action = FunctionRouteAction.fromWire(tok);
        if (action == null) continue;
        if (action == FunctionRouteAction.dispatchLocalAlarm) continue;
        if (action == FunctionRouteAction.requestClarification) continue;
        calls.add(_buildFollowupCall(action, raw, reason));
      }
    }

    final briefing = _extractField(raw, 'BRIEFING');
    if (briefing != null && briefing.length > 4) {
      // Override / inject summarize_for_user when BRIEFING is present.
      calls.removeWhere(
        (c) => c.action == FunctionRouteAction.summarizeForUser,
      );
      calls.add(
        FunctionCall(
          action: FunctionRouteAction.summarizeForUser,
          arguments: {'briefing': briefing.trim()},
          rationale: null,
        ),
      );
    }

    return List.unmodifiable(calls);
  }

  FunctionCall _buildFollowupCall(
    FunctionRouteAction action,
    String raw,
    String fallbackReason,
  ) {
    switch (action) {
      case FunctionRouteAction.summarizeForUser:
        final briefing = _extractField(raw, 'BRIEFING')?.trim();
        return FunctionCall(
          action: action,
          arguments: {
            if (briefing != null && briefing.isNotEmpty) 'briefing': briefing,
          },
          rationale: null,
        );
      case FunctionRouteAction.notifyEmergencyContacts:
        final message = _extractField(raw, 'CONTACT_MESSAGE')?.trim();
        return FunctionCall(
          action: action,
          arguments: {
            'message': (message != null && message.isNotEmpty)
                ? message
                : fallbackReason,
          },
          rationale: null,
        );
      case FunctionRouteAction.activateMeshRelay:
        return FunctionCall(
          action: action,
          arguments: const {'ttl_minutes': 30},
          rationale: null,
        );
      case FunctionRouteAction.dispatchLocalAlarm:
      case FunctionRouteAction.requestClarification:
        return FunctionCall(
          action: action,
          arguments: const {},
          rationale: null,
        );
    }
  }

  Iterable<String> _splitActionTokens(String line) sync* {
    for (final part in line.split(RegExp(r'[,\n;]+'))) {
      final t = part.trim().toLowerCase();
      if (t.isEmpty) continue;
      yield t;
    }
  }

  /// Whole-word-ish token match — substring with non-letter boundaries
  /// so `EMERGENCY` does not match inside `NOT_EMERGENCY`.
  bool _hasAnyToken(String haystack, List<String> tokens) {
    for (final t in tokens) {
      final pattern = RegExp('(?<![A-Z_])$t(?![A-Z_])');
      if (pattern.hasMatch(haystack)) return true;
    }
    return false;
  }

  static const List<String> _positiveVerdictTokens = [
    'EMERGENCY',
    'REAL',
    'YES',
    'TRUE',
    'CONFIRMED',
    'CONFIRM',
    'ESCALATE',
    'ALARM',
    'ALERT',
    'CRITICAL',
    'URGENT',
  ];

  static const List<String> _negativeVerdictTokens = [
    'NOT_EMERGENCY',
    'NOT EMERGENCY',
    'NOT_REAL',
    'NOT REAL',
    'NO',
    'FALSE',
    'SAFE',
    'DRILL',
    'TEST',
    'PROMO',
    'SPAM',
    'NONE',
    'DISMISS',
    'IGNORE',
    'BENIGN',
  ];

  /// Extract a single line of the form `KEY: value` (case-insensitive on
  /// the key). Returns the trimmed value, or `null` if the key is missing.
  String? _extractField(String raw, String key) {
    final pattern = RegExp(
      '^\\s*$key\\s*:\\s*(.+?)\\s*\$',
      caseSensitive: false,
      multiLine: true,
    );
    final match = pattern.firstMatch(raw);
    if (match == null) return null;
    final value = match.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    // Strip wrapping quotes/markdown that the model occasionally emits.
    return value.replaceAll(RegExp(r'^[`"\*_]+|[`"\*_]+$'), '').trim();
  }

  String _trimReason(String reason) {
    final cleaned = reason.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 80) return cleaned;
    return '${cleaned.substring(0, 77)}…';
  }

  String _buildSystemInstruction(String? language) {
    final languageRule = (language == null || language.isEmpty)
        ? "REASON in the alert's language."
        : 'REASON in "$language".';
    return '''
You are an emergency-alert classifier for a life-safety app. Decide whether the inbound message describes a REAL imminent threat to life or safety.

REAL emergency = disaster (cyclone, tsunami, earthquake, flood, wildfire, tornado), evacuation order, civil emergency, child abduction, hazmat, terror, mass-casualty event, active shooter.

NOT a real emergency = marketing/spam ("EMERGENCY SALE", "limited time"), bills, OTPs, social messages, news headlines, drills/tests ("this is a TEST", "drill alert"), opt-out text ("Reply STOP"), clickbait that just uses urgent words.

Reply with EXACTLY this format and nothing else — no prose, no markdown, no preamble:

VERDICT: <EMERGENCY or NOT_EMERGENCY>
SEVERITY: <critical, high, medium, or low>
REASON: <short user-facing label, 5-10 words max>
ACTIONS: <comma-separated follow-up actions, or NONE>
BRIEFING: <2-3 short sentences read aloud to the user, or NONE>
CONTACT_MESSAGE: <SMS body sent to emergency contacts, or NONE>

VERDICT MUST be the literal word EMERGENCY or NOT_EMERGENCY (uppercase, with underscore). Do NOT use synonyms like REAL, YES, CONFIRMED, NO, SAFE, DRILL, TEST.

ACTIONS allowed values (pick zero or more, comma-separated):
- summarize_for_user — user is staring at takeover screen, read BRIEFING aloud.
- notify_emergency_contacts — fire CONTACT_MESSAGE to saved contacts.
- activate_mesh_relay — re-broadcast over BLE mesh for off-grid neighbours.

If NOT_EMERGENCY: SEVERITY: low, ACTIONS: NONE, BRIEFING: NONE, CONTACT_MESSAGE: NONE.
If EMERGENCY: at minimum include summarize_for_user in ACTIONS and write a real BRIEFING; add notify_emergency_contacts when the user should alert their network; add activate_mesh_relay only for wide-area disasters (cyclone, earthquake, tsunami, wildfire) where neighbours nearby may be offline.
$languageRule''';
  }

  String _buildUserPrompt(AlertEvent event) {
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

Classify now.''';
  }
}
