import 'package:equatable/equatable.dart';

/// The fixed catalog of actions Aegis exposes to the FunctionGemma router.
///
/// FunctionGemma 270M (and Gemma 4 standing in for it) is prompted with a
/// description of these tools and is expected to emit one or more
/// `<start_function_call>...<end_function_call>` blocks naming an action
/// from this enum and supplying JSON arguments. Keeping the catalog as a
/// closed enum (rather than free-form strings) lets the dispatcher in
/// [`AlertRouter`] use exhaustive `switch` and reject any hallucinated
/// action name before it reaches a handler.
///
/// Wire-format names match the strings the model emits in its JSON
/// payloads. Keep them snake_case to line up with the FunctionGemma
/// pretraining vocabulary; renaming them is a router-prompt-and-parser
/// breaking change.
enum FunctionRouteAction {
  /// Re-arm / continue the local ringer + full-screen alert without any
  /// extra reasoning. The router picks this when the regex classifier
  /// already established the alert is real and severity is high enough.
  dispatchLocalAlarm('dispatch_local_alarm'),

  /// Generate a one-paragraph briefing the TTS layer can read aloud while
  /// the user is staring at the takeover screen. Useful when the alert
  /// body is long, multilingual, or full of jargon.
  summarizeForUser('summarize_for_user'),

  /// Notify the user's saved emergency contacts. Stubbed in Sprint 2 — the
  /// real channel-out (SMS / share / call) lands in Sprint 4.
  notifyEmergencyContacts('notify_emergency_contacts'),

  /// Hand the alert payload to the BLE mesh stub so neighbours without
  /// cell signal can be re-broadcast to. Sprint 5 fills this in for real.
  activateMeshRelay('activate_mesh_relay'),

  /// Router was uncertain. Used as a fallback when the model's confidence
  /// is low or the alert body is contradictory. The handler logs this and
  /// keeps the user on the takeover screen so they can tap through.
  requestClarification('request_clarification');

  const FunctionRouteAction(this.wireName);

  /// JSON-safe name the model is expected to emit. Round-trips through
  /// [fromWire] when parsing.
  final String wireName;

  static FunctionRouteAction? fromWire(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final action in FunctionRouteAction.values) {
      if (action.wireName == normalized) return action;
    }
    return null;
  }
}

/// A single function-call block successfully parsed out of the model's
/// output. The router preserves order so handlers fire in the sequence
/// the model intended (e.g. `dispatch_local_alarm` then `summarize_for_user`).
class FunctionCall extends Equatable {
  const FunctionCall({
    required this.action,
    required this.arguments,
    this.rationale,
  });

  final FunctionRouteAction action;

  /// Arbitrary JSON-decoded payload. Handlers cast / read the shape they
  /// expect; the parser does no schema validation beyond "this was valid
  /// JSON inside the fence". Keep the shape small — FunctionGemma is
  /// terrible at filling deeply nested structures reliably.
  final Map<String, dynamic> arguments;

  /// Optional model-supplied "why" string. We store it for telemetry and
  /// debug overlays but never feed it back into the prompt.
  final String? rationale;

  @override
  List<Object?> get props => [action, arguments, rationale];

  @override
  String toString() =>
      'FunctionCall(${action.wireName}, args=$arguments'
      '${rationale == null ? '' : ', rationale="$rationale"'})';
}

/// Schema descriptor used when building the router prompt. We embed each
/// definition's `name`, `description`, and JSON-shaped `parameters` block
/// directly into the system instruction so the model has a stable
/// vocabulary to draw from. This mirrors the OpenAI / Gemini "tools"
/// payload shape, which both Gemma 3n and the published FunctionGemma 270M
/// were fine-tuned on.
class FunctionDefinition extends Equatable {
  const FunctionDefinition({
    required this.action,
    required this.description,
    required this.parameters,
  });

  /// The route this definition advertises. The wire name comes from
  /// [FunctionRouteAction.wireName] so prompt and parser stay in sync.
  final FunctionRouteAction action;

  /// One-sentence explanation the model uses to choose between actions.
  /// Be concrete: "Trigger the local siren and full-screen takeover for
  /// a confirmed emergency." beats "Triggers an alarm.".
  final String description;

  /// JSON-schema-style argument shape. Keep it shallow (string / number /
  /// boolean / enum). Anything more complex tends to come back malformed.
  final Map<String, dynamic> parameters;

  Map<String, dynamic> toJson() => {
    'name': action.wireName,
    'description': description,
    'parameters': parameters,
  };

  @override
  List<Object?> get props => [action, description, parameters];
}

/// The default tool catalog wired into the router. Centralised here so
/// every consumer (prompt builder, parser allow-list, dispatcher) reads
/// from the same source of truth.
const List<FunctionDefinition> defaultFunctionDefinitions = [
  FunctionDefinition(
    action: FunctionRouteAction.dispatchLocalAlarm,
    description:
        'Trigger the local siren plus full-screen takeover for a confirmed '
        'emergency. Use when the alert is credible AND immediate physical '
        'action is required (evacuate, take cover, move to higher ground).',
    parameters: {
      'type': 'object',
      'properties': {
        'severity': {
          'type': 'string',
          'enum': ['critical', 'high', 'medium', 'low'],
          'description': 'Final severity to display to the user.',
        },
        'reason': {
          'type': 'string',
          'description': 'Short user-facing label e.g. "Tsunami evacuation".',
        },
      },
      'required': ['severity', 'reason'],
    },
  ),
  FunctionDefinition(
    action: FunctionRouteAction.summarizeForUser,
    description:
        'Produce a short spoken briefing of what happened and what to do, '
        'in the user\'s preferred language. Use when the source text is '
        'long, multilingual, or technical.',
    parameters: {
      'type': 'object',
      'properties': {
        'language': {
          'type': 'string',
          'description': 'BCP-47 / ISO-639 code, e.g. "en", "hi", "th".',
        },
        'briefing': {
          'type': 'string',
          'description': 'Plain-language summary, under 60 words.',
        },
      },
      'required': ['briefing'],
    },
  ),
  FunctionDefinition(
    action: FunctionRouteAction.notifyEmergencyContacts,
    description:
        'Send the alert summary to the user\'s saved emergency contacts. '
        'Only call when the alert is critical or the user is likely '
        'incapacitated (e.g. earthquake, severe injury context).',
    parameters: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description': 'Message body to send to contacts.',
        },
      },
      'required': ['message'],
    },
  ),
  FunctionDefinition(
    action: FunctionRouteAction.activateMeshRelay,
    description:
        'Re-broadcast the alert over the BLE mesh so neighbours without '
        'cellular reception receive it. Call for any credible regional '
        'hazard (tsunami, cyclone, earthquake, hazmat).',
    parameters: {
      'type': 'object',
      'properties': {
        'ttl_minutes': {
          'type': 'integer',
          'description': 'How long the relay should keep advertising.',
        },
      },
      'required': [],
    },
  ),
  FunctionDefinition(
    action: FunctionRouteAction.requestClarification,
    description:
        'The router could not decide. Falls back to keeping the takeover '
        'screen visible so the user can read the raw text and choose.',
    parameters: {
      'type': 'object',
      'properties': {
        'reason': {
          'type': 'string',
          'description': 'Why the router was uncertain.',
        },
      },
      'required': [],
    },
  ),
];
