import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../places/map_view_query.dart';
import '../skills/skills_registry.dart';
import 'model_pack.dart';
import 'model_registry.dart';
import 'triage_input.dart';
import 'triage_report.dart';

export '../places/map_view_query.dart' show ChatStreamEvent, ChatTextChunk,
    ChatMapCall, MapViewQuery;

/// Persistence port for the hardware-fallback sentinels owned by
/// [LlmService]. Lives behind an interface so the LLM core never
/// depends on `StorageService` directly — tests pass a stub.
///
/// The two flags are sticky escape hatches for devices where
/// LiteRT-LM's GPU path corrupts the process-wide GL/CL context on
/// failure (`clEnqueueMapBuffer -14`, `STABLEHLO_COMPOSITE failed to
/// prepare`, `convert_tensor_buffer` reshape error). Once tripped,
/// the next cold launch starts on the safe path.
abstract interface class HardwareFallbackStore {
  bool readForceCpu();
  bool readDisableVision();
  Future<void> persistForceCpu();
  Future<void> persistDisableVision();

  /// Clear the persisted `forceCpu` flag. Used at boot to migrate
  /// installs from older builds that persisted CPU mode (which on this
  /// bundle wedges the engine at XNNPack-incompatible DYNAMIC_UPDATE_
  /// SLICE nodes). Safe to call when the flag is already false.
  Future<void> clearForceCpu();

  /// Clear the persisted `disableVision` flag. Used at boot to migrate
  /// installs that flipped vision off after a warmup-induced GPU
  /// poisoning — once warmup is gone, vision works again. Safe to
  /// call when the flag is already false.
  Future<void> clearDisableVision();
}

/// Reserved Gemma / LiteRT-LM tokens that should never appear in a final
/// user-facing reply. Catches `<unused3>`, `<mask>`, leftover chat-template
/// markers, etc.
final RegExp _reservedToken = RegExp(
  r'<\|?(?:'
  r'unused\d+|mask|pad|eos|bos|unk|sep|cls'
  r'|start_of_turn|end_of_turn|start_of_image|end_of_image'
  r'|extra_id_\d+'
  r'|turn|think|channel|im_start|im_end'
  r')\|?>',
);

/// Gemma 4 IT chain-of-thought delimiters. With `enableThinking: true`
/// the model wraps its scratchpad in these markers and emits the real
/// reply after `<channel|>`.
const String _thinkStart = '<|channel>thought\n';
const String _thinkEnd = '<channel|>';
final RegExp _thinkBlockRegex = RegExp(
  r'<\|channel>thought\n.*?<channel\|>',
  dotAll: true,
);

final RegExp _leadingQuote = RegExp(
  r'''^(?:"|“|'|`)+\s*|\s*(?:"|”|'|`)+$''',
);

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

/// ISO-639 → human-readable name.
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

/// Emergency-assistant system prompt shared by every chat session.
///
/// Tuned for ACTIONABLE help. Earlier versions ended every reply with a
/// single "call emergency services" sentence — useless when the user is
/// already injured and alone. The model now leads with first-aid /
/// protective steps and only THEN reminds them to call for help. The
/// "call services" line never replaces actionable guidance.
const String _aegisSystemPromptTemplate = '''
You are Aegis, an offline emergency assistant. User is likely injured,
in danger, or helping someone who is. Give concrete steps they can do
with their hands NOW.

On every turn:

1. Clear emergency → numbered list, 3-6 short action steps (stop
   bleeding, get to shelter, check breathing, move from hazard).

2. Injury → standard first-aid for that injury. Specific, physical
   (firm pressure on bleed, cool water on burn, don't move spine).

3. After steps, ONE line telling them to also call emergency services
   if not already. Never make "call for help" the whole answer.

4. Plain language. Short sentences. No jargon. One acknowledging line
   before steps if user sounds panicked or hurt.

5. CLARIFY: If message is not a specific emergency/injury/hazard,
   skip steps and ask ONE direct question. Never guess. Never invent
   a scenario.

6. NEARBY-PLACES RULE: User asks about any nearby facility (hospital,
   shelter, fuel, pharmacy, water, ATM, police, fire station, food,
   charging) in any language → call `render_map_view`. Do NOT ask
   for their location. `spoken_summary` argument is your one-line
   reply in the user's language.

7. LANGUAGE RULE: Reply in the same language the user wrote in. No
   switching, no mixing.

8. Unknown facts (phone numbers, addresses, drug doses): say so
   plainly. Never invent.

9. 60-140 words. Long enough to help, short enough for a phone screen.
''';

String _buildSystemPrompt(String? languageCode, {String? briefingContext}) {
  final code = languageCode?.toLowerCase();
  final name = code == null ? null : _languageNames[code];
  final rule = name == null
      ? 'Reply in the same language the user spoke.'
      : 'Always reply in $name. Do not switch to any other language even '
            'if the user mixes English words. Use the native script for '
            '$name (not romanized text).';
  final base = _aegisSystemPromptTemplate.replaceFirst('{language_rule}', rule);
  if (briefingContext == null || briefingContext.trim().isEmpty) return base;
  // Append the briefing so the model knows what just happened — the
  // user can then ask follow-ups ("what should I do?", "where is the
  // nearest shelter?") without re-explaining the situation. Kept as a
  // short addendum to avoid bloating prefill cost.
  return '$base\n\nRecent emergency context (do not repeat verbatim): '
      '${briefingContext.trim()}';
}

/// JSON Schema for the `render_triage_report` tool. Native function
/// calling on Gemma 4 routes this through LiteRT-LM
/// `litert_lm_conversation_config_set_tools` — the SDK applies
/// `chat_template.jinja` (via `minja`) to render
/// `<|tool>declaration:…<tool|>` tokens, and the model's
/// `<|tool_call>…<tool_call|>` response comes back as a structured
/// [FunctionCallResponse].
const Map<String, Object?> _triageToolSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'format': <String, Object?>{
      'type': 'string',
      'description': 'Report template. Default ICS-209.',
      'enum': <String>[
        'ICS-209',
        'OCHA_SITREP',
        'UN_FLASH_UPDATE',
        'NDRRMC',
        'IFRC_OPS_UPDATE',
        'EU_ECHO_FLASH',
        'PDNA',
      ],
    },
    'title': <String, Object?>{
      'type': 'string',
      'description': 'Short incident title (e.g. Building Collapse Incident).',
    },
    'severity': <String, Object?>{
      'type': 'string',
      'description':
          'CRITICAL=life-threatening/mass-casualty; HIGH=serious damage or one trapped; MODERATE=minor; LOW=property only; INFO=unsure.',
      'enum': <String>['CRITICAL', 'HIGH', 'MODERATE', 'LOW', 'INFO'],
    },
    'hazard_type': <String, Object?>{
      'type': 'string',
      'description':
          'Primary hazard. STRUCTURAL_DAMAGE=collapsed building; FIRE=flame/smoke; FLOOD=water; HAZMAT=chemical/gas; CASUALTY=injured person; MISSING_PERSON; MEDICAL=non-trauma; EVACUATION; OTHER fallback.',
      'enum': <String>[
        'STRUCTURAL_DAMAGE',
        'CASUALTY',
        'MISSING_PERSON',
        'FIRE',
        'FLOOD',
        'HAZMAT',
        'MEDICAL',
        'EVACUATION',
        'OTHER',
      ],
    },
    'summary': <String, Object?>{
      'type': 'string',
      'description':
          'Card subtitle, 1-2 sentences, <=180 chars, what is happening now.',
    },
    'immediate_actions': <String, Object?>{
      'type': 'array',
      'description':
          'EXACTLY 3-5 imperative responder steps. Each 10-80 chars, non-empty, unique. Example item: "Evacuate the north flank".',
      'minItems': 3,
      'maxItems': 5,
      'items': <String, Object?>{
        'type': 'string',
        'minLength': 10,
        'maxLength': 80,
      },
    },
    'body': <String, Object?>{
      'type': 'string',
      'minLength': 600,
      'description':
          'Report body 800-1800 chars. Five UPPERCASE section headings each on own line. Each section MUST be Label: value rows (no prose paragraphs). Sections in this order: SITUATION, PUBLIC IMPACT, STRUCTURES, RESPONSE, OUTLOOK. Rules: write a number when visible ("3 visible"); estimate with "likely" / "~5 estimated" when implied; "0 reported" only when scene truly shows zero. Include construction type in STRUCTURES. RESPONSE has both Resources deployed AND Gaps rows. OUTLOOK includes a time horizon. NEVER include rows for title, severity, summary, immediate_actions, GPS, date/time, hazard_type, casualty_*, fema_*, hazus_*, recommended_skill — those live in separate fields.\n\nFORMAT EXEMPLAR (mirror this row pattern in every report, vary the values):\nSITUATION\nNarrative: Concrete mid-rise partially collapsed; debris to knee height; daylight, partial overcast.\n\nPUBLIC IMPACT\nFatal: 0 reported\nInjured: ~3 estimated based on collapse footprint\nMissing: 2 likely\nDisplaced: 0 reported\n\nSTRUCTURES\nThreatened: 2 adjacent residential\nDamaged: 1 mid-rise concrete (partial collapse)\nDestroyed: 0\nConstruction Type: reinforced concrete\n\nRESPONSE\nResources deployed: 1 ambulance, 4 high-vis responders visible\nGaps: no heavy-lift crane, no triage tent, no fire suppression\n\nOUTLOOK\nProjected activity: search-and-rescue ops over next 6-12h; access via north flank only\nConcerns: secondary collapse risk from saturated debris over next 24h',
    },
    // NB: `gps` and `prepared_at` are intentionally NOT exposed to the
    // model. We saw the model drop leading digits ("19.20337" →
    // "9.20337"), invent latitudes, and emit mangled timestamps
    // ("206-0-12011110557Z") even with verbatim-copy instructions.
    // Both fields are deterministic — the device already knows them —
    // so we inject ground truth in [_finaliseReport] after the tool
    // call returns. Keeps these fields 100% accurate, removes the
    // hallucination surface, and frees up decode tokens.
    'hazus_category': <String, Object?>{
      'type': 'integer',
      'description':
          'FEMA HAZUS damage category 0-4 (None/Slight/Moderate/Extensive/Complete). Set when a damage photo was analysed; omit otherwise.',
    },
    'fema_scale': <String, Object?>{
      'type': 'string',
      'description': 'HAZUS label string paired with hazus_category.',
      'enum': <String>[
        'HAZUS_NONE',
        'HAZUS_SLIGHT',
        'HAZUS_MODERATE',
        'HAZUS_EXTENSIVE',
        'HAZUS_COMPLETE',
      ],
    },
    'damage_description': <String, Object?>{
      'type': 'string',
      'description':
          'One-line damage description from the photo. Omit when no image attached.',
    },
    'casualty_status': <String, Object?>{
      'type': 'string',
      'description':
          'START triage status for the primary affected person. Set when the user describes a casualty.',
      'enum': <String>[
        'ALIVE_SAFE',
        'ALIVE_INJURED',
        'ALIVE_TRAPPED',
        'ALIVE_UNKNOWN',
        'MISSING',
        'DECEASED',
      ],
    },
    'casualty_count': <String, Object?>{
      'type': 'integer',
      'description':
          'Number of people affected when the user gave a count. Omit when unknown.',
    },
    'casualty_triage_color': <String, Object?>{
      'type': 'string',
      'description': 'START triage color paired with casualty_status.',
      'enum': <String>['RED', 'YELLOW', 'GREEN', 'BLACK', 'UNTAGGED'],
    },
    'recommended_skill': <String, Object?>{
      'type': 'string',
      'description':
          'Skill id from the catalog that the responder should run next. Omit when none applies.',
    },
    'spoken_summary': <String, Object?>{
      'type': 'string',
      'description':
          'Optional natural-language sentence (<=2 sentences) for the TTS to read aloud while the card mounts. Omit on responder-mode turns where the card alone suffices.',
    },
  },
  'required': <String>[
    'format',
    'title',
    'severity',
    'summary',
    'body',
    'immediate_actions',
  ],
};

/// Single tool exposed to Gemma 4 for the triage path. The model
/// emits one call to this tool per triage turn; arguments map 1:1 to
/// [TriageReport] fields.
final Tool _renderTriageReportTool = const Tool(
  name: 'render_triage_report',
  description:
      'Render a structured incident report card and read out an optional spoken summary. Call exactly once per triage turn. Pick fields from the user\'s evidence (text, photo, audio, GPS). Do not invent locations or identifiers absent from the input.',
  parameters: _triageToolSchema,
);

/// JSON Schema for the chat-path `render_map_view` tool. Mirrors the
/// `find-nearby-places` skill: a closed-vocabulary list of categories
/// plus a search radius and a short spoken summary. The Flutter layer
/// resolves the actual GPS / region centre and runs the offline POI
/// query — the model only commits to *intent*.
const Map<String, Object?> _mapViewToolSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'categories': <String, Object?>{
      'type': 'array',
      'description':
          'POI categories to look for. Pick one or more from the closed list. Use multiple when the user is vague ("find help") — default to shelter+hospital+water_point in that case.',
      'minItems': 1,
      'maxItems': 5,
      'items': <String, Object?>{
        'type': 'string',
        'enum': <String>[
          'shelter',
          'hospital',
          'clinic',
          'pharmacy',
          'water_point',
          'food_distribution',
          'fuel_station',
          'atm',
          'police',
          'fire_station',
          'charging_point',
          'connectivity_point',
        ],
      },
    },
    'radius_km': <String, Object?>{
      'type': 'number',
      'description':
          'Search radius in kilometres. 2-10 km typical. Use the smaller end for water/ATM/pharmacy, larger for shelter/hospital.',
      'minimum': 1,
      'maximum': 50,
    },
    'spoken_summary': <String, Object?>{
      'type': 'string',
      'description':
          'One short sentence the TTS reads aloud while the map mounts. Examples: "Showing the nearest shelters.", "Three open hospitals nearby — closest is 1.2 km away." Keep under 25 words.',
    },
  },
  'required': <String>['categories', 'spoken_summary'],
};

/// Chat-path tool. Gemma 4 calls this when the user asks about nearby
/// critical facilities; the cubit resolves location + POIs from the
/// offline DB and pins an inline map card onto the conversation turn.
///
/// Description is intentionally short — bundle's `prefill_1024`
/// ceiling rejects oversized tool declarations after jinja-render.
/// Multilingual trigger coverage lives in the per-turn nudge
/// ([_hasNearbyPlacesIntent]) + system prompt's NEARBY-PLACES RULE.
final Tool _renderMapViewTool = const Tool(
  name: 'render_map_view',
  description:
      'Render an inline map of nearby disaster-critical places (shelter, hospital, clinic, pharmacy, water, food, fuel, ATM, police, fire station, charging, connectivity). Call when the user asks where to find or how to reach any such place, in ANY language. App already knows the user\'s GPS — never ask for their location. `spoken_summary` is in the user\'s language.',
  parameters: _mapViewToolSchema,
);

/// Wraps flutter_gemma's modern API so the rest of the app can treat
/// the LLM as a simple text-in/text-out (and audio-in/text-out) service.
///
/// **Two roles, one model.** Gemma 4 plays two parts here:
///   * **ASR** for [transcribeAudio] — speech → text.
///   * **Aegis assistant** for [ask] / [askStream] — chat replies, and
///     [generateReport] — structured triage analysis via native
///     `render_triage_report` tool call.
///
/// flutter_gemma 0.15.0's `ModelType.gemma4` routes the tool definition
/// to LiteRT-LM (`litert_lm_conversation_config_set_tools`) — the SDK
/// applies `chat_template.jinja` through `minja`, emits native
/// `<|tool>declaration:…<tool|>` tokens for the model, and parses the
/// `<|tool_call>…<tool_call|>` response back into a structured
/// [FunctionCallResponse]. No Dart-side prompt engineering.
class LlmService {
  LlmService(
    this._registry, {
    SkillsRegistry? skills,
    HardwareFallbackStore? hardwareStore,
  })  : _skills = skills ?? SkillsRegistry(),
        _hardwareStore = hardwareStore {
    // Honor persisted hardware-fallback sentinels at construction so
    // the first engine_create on this process boots on the safe path.
    //
    // NB: we DELIBERATELY no longer honor `forceCpuBackend` at boot.
    // The Gemma 4 E2B .litertlm bundle has a DYNAMIC_UPDATE_SLICE
    // node (1164) that XNNPack rejects at delegate-prepare time —
    // CPU mode is 100% broken on this bundle. Persisting CPU would
    // wedge the app on every cold launch. We still flip CPU in-process
    // when GPU dies (so the user gets one usable retry within the
    // session), but the next cold launch always retries GPU.
    final store = _hardwareStore;
    if (store != null) {
      // Migration: clear forceCpu (broken on this bundle) and
      // disableVision (poisoning was caused by boot-time warmup, now
      // removed) so existing installs get vision back without needing
      // an uninstall. New crashes will re-flip both as needed.
      if (store.readForceCpu()) {
        unawaited(store.clearForceCpu());
      }
      if (store.readDisableVision()) {
        unawaited(store.clearDisableVision());
      }
    }
  }

  final ModelRegistry _registry;
  final SkillsRegistry _skills;

  /// Optional persistent flag store. When supplied, GPU / vision crashes
  /// flip + persist a sentinel so the next cold launch starts on the
  /// safe path. Decoupled from `StorageService` so the LLM core stays
  /// independent of the Hive layer in tests.
  final HardwareFallbackStore? _hardwareStore;

  /// Session-scoped circuit breaker for the vision decoder. Once a
  /// vision-decode crash fires we strip the image from subsequent
  /// triage calls in the same process AND persist via
  /// [_hardwareStore] so future launches skip vision too.
  bool _visionDisabled = false;

  // Single LLM role. We retired the FunctionGemma 270M router pack — the
  // chat brain (Gemma 4 IT) doubles as the alert-routing classifier via
  // [oneShot] (history-free fresh session). flutter_gemma 0.13.6 only
  // allows one model loaded at a time, which is now a non-issue since
  // there is only ever one pack.
  VoiceModelPack? _chatPack;

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
  String? _briefingContext;
  Future<void> _oneShotChain = Future<void>.value();

  SkillsRegistry get skills => _skills;

  /// Backend used at every engine_create. Hardcoded to GPU — this
  /// bundle's CPU XNNPack path rejects `DYNAMIC_UPDATE_SLICE` at node
  /// 1164 and fails at delegate-prepare time, so a CPU fallback is
  /// worse than no fallback. GPU crashes are recovered by disposing
  /// the engine + flipping `_visionDisabled` (see
  /// [_shouldFallbackToCpu]) and retrying on GPU.
  final PreferredBackend _preferredBackend = PreferredBackend.gpu;

  /// The pack the engine is currently loaded against (or about to be on
  /// the next [ask]/[oneShot] call). Null until [setChatPack] / [setPack]
  /// has been called.
  VoiceModelPack? get pack => _activePack;

  /// Convenience accessor.
  VoiceModelPack? get chatPack => _chatPack;

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

  /// Synchronous engine swap: replace [_activePack] and tear down anything
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

  void setPreferredLanguage(String? languageCode) {
    final normalized = (languageCode == null || languageCode.isEmpty)
        ? null
        : languageCode.toLowerCase();
    if (_preferredLanguage == normalized) return;
    _preferredLanguage = normalized;
    unawaited(_disposeChat());
  }
  /// Pin a recent emergency-alert briefing into the chat brain's
  /// system prompt as an addendum. The next chat session will be built
  /// with the briefing appended after the base system prompt, so when
  /// the user asks a follow-up ("what should I do?", "where is the
  /// nearest shelter?") the model already has the disaster context
  /// without the user re-explaining it. Pass `null` to clear.
  ///
  /// Tears down the cached chat so the new system prompt takes effect
  /// — system prompt is prefilled at chat creation time.
  void setBriefingContext(String? briefing) {
    final normalized = briefing?.trim();
    final next = (normalized == null || normalized.isEmpty) ? null : normalized;
    if (_briefingContext == next) return;
    _briefingContext = next;
    unawaited(_disposeChat());
  }

  /// True if the currently-active pack is installed on disk.
  Future<bool> isAvailable() async {
    final pack = _activePack;
    if (pack == null) return false;
    return _registry.isInstalled(pack);
  }

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
    await _disposeChat();
    final model = await _ensureModel(maxTokens: 1024);
    final prompt = _buildAsrPrompt(language);
    final session = await model.createSession(
      temperature: 0.0,
      randomSeed: 1,
      topK: 1,
      enableAudioModality: true,
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
        // best-effort
      }
    }
  }

  String _buildAsrPrompt(String? language) {
    final name = language == null ? null : _languageNames[language.toLowerCase()];
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
    final lowered = normalized.toLowerCase();
    var cutAt = normalized.length;
    for (final marker in _asrEchoMarkers) {
      final idx = lowered.indexOf(marker);
      if (idx >= 0 && idx < cutAt) cutAt = idx;
    }
    if (cutAt < normalized.length) {
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

  /// Stream a response as a mixed sequence of [ChatTextChunk] (text tokens
  /// for the running TTS sentence flusher) and [ChatMapCall] (Gemma 4
  /// emitted a `render_map_view` native function call). The stream
  /// finishes when the model signals EOS.
  ///
  /// flutter_gemma 0.15.0's `Stream<ModelResponse>` already interleaves
  /// `TextResponse` and `FunctionCallResponse` events from the same
  /// session — we just translate types here so the cubit never has to
  /// reach into the SDK.
  Stream<ChatStreamEvent> askStream(
    String userText, {
    int maxTokens = 1024,
  }) async* {
    try {
      yield* _askStreamOnce(userText, maxTokens: maxTokens);
    } on Object catch (e) {
      if (!await _shouldFallbackToCpu(e)) rethrow;
      yield* _askStreamOnce(userText, maxTokens: maxTokens);
    }
  }

  /// Crisis-loop entry point. Runs Gemma 4 with the
  /// `render_triage_report` tool exposed via `ModelType.gemma4` native
  /// function calling and returns the parsed [TriageReport].
  ///
  /// Returns null when the model emitted a plain text reply instead of
  /// a tool call (caller should fall back to showing the text). Throws
  /// on unrecoverable engine errors.
  Future<TriageReport?> generateReport(
    TriageInput input, {
    int maxTokens = 4096,
  }) async {
    try {
      return await _generateReportOnce(input, maxTokens: maxTokens);
    } on Object catch (e) {
      if (await _shouldFallbackToCpu(e)) {
        return _generateReportOnce(input, maxTokens: maxTokens);
      }
      if (await _shouldFallbackToSmallerContext(e, maxTokens)) {
        return _generateReportOnce(input, maxTokens: 2048);
      }
      if (await _shouldFallbackToTextOnly(e, input)) {
        // Image decode crashed on this device's GPU. Strip vision and
        // retry text-only so the responder still gets a report from the
        // voice / text / GPS signals.
        final downgraded = TriageInput(
          userText: input.userText,
          audioWav: input.audioWav,
          imageJpeg: null,
          gpsContext: input.gpsContext,
          incidentLog: input.incidentLog,
          activeRegionPackId: input.activeRegionPackId,
          requestId: input.requestId,
        );
        return _generateReportOnce(downgraded, maxTokens: maxTokens);
      }
      rethrow;
    }
  }

  Future<bool> _shouldFallbackToSmallerContext(
    Object error,
    int currentMaxTokens,
  ) async {
    if (currentMaxTokens <= 2048) return false;
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
        'falling back to 2048: $error',
      );
    }
    await _disposeModel();
    return true;
  }

  /// LiteRT-LM occasionally crashes in `convert_tensor_buffer` /
  /// `llm_litert_compiled_model_executor` when the vision decoder's
  /// output tensor can't be reshaped on this device's GPU (Mali devices
  /// with both OpenCL AND WebGPU samplers missing fall to CPU
  /// sampling, which then trips up the vision-conditioned decoder).
  /// When that happens, we tear the engine down and retry the SAME
  /// triage turn with the image stripped — text + audio + GPS still
  /// produce a usable report.
  Future<bool> _shouldFallbackToTextOnly(
    Object error,
    TriageInput input,
  ) async {
    if (!input.hasImage) return false;
    final message = error.toString();
    final isTensorBufferError =
        message.contains('convert_tensor_buffer') ||
            message.contains('litert_tensor_buffer') ||
            message.contains('llm_litert_compiled_model_executor') ||
            message.contains('INTERNAL: ERROR');
    if (!isTensorBufferError) return false;
    if (kDebugMode) {
      debugPrint(
        '[Aegis][LLM] tensor-buffer error during vision decode; '
        'flipping circuit breaker (vision disabled) and retrying '
        'triage text-only: $error',
      );
    }
    // Session circuit breaker: this device's vision path is unstable.
    // Subsequent triage calls inside the same process strip the image
    // before reaching the LLM (see [_generateReportOnce]). Persist the
    // sentinel so cold launches honor the same skip — kicking the bug
    // forever is better than rolling the dice on each turn.
    _visionDisabled = true;
    final store = _hardwareStore;
    if (store != null) {
      try {
        await store.persistDisableVision();
        if (kDebugMode) {
          debugPrint(
            '[Aegis][LLM] persisted disableVision=true after vision crash',
          );
        }
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint('[Aegis][LLM] persistDisableVision failed: $e');
        }
      }
    }
    return true;
  }

  Future<TriageReport?> _generateReportOnce(
    TriageInput input, {
    required int maxTokens,
  }) async {
    // Triage uses a dedicated one-shot session so the tool-exposed
    // chat history doesn't poison the persistent Ask chat. Tear the
    // chat down first to free the model's single session slot.
    await _disposeChat();
    // Snapshot ground-truth values BEFORE the LLM runs so the
    // post-process injection uses the moment-of-capture timestamp,
    // not whenever the engine happens to return.
    final capturedAt =
        '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final groundGps = input.gpsContext ?? '';
    // Honor the vision circuit breaker. When [_visionDisabled] is set
    // (in-memory after a prior crash this session, or persisted from a
    // previous launch), strip the image up front so we never feed the
    // broken vision path again. Audio + text + GPS still produce a
    // usable report.
    final effectiveImage =
        _visionDisabled ? null : input.imageJpeg;
    final hasImage = effectiveImage != null && effectiveImage.isNotEmpty;
    if (kDebugMode && _visionDisabled && input.hasImage) {
      debugPrint(
        '[Aegis][LLM] vision circuit breaker active — stripping image '
        'from triage input',
      );
    }
    final model = await _ensureModel(maxTokens: maxTokens);
    final systemPrompt = await _buildTriageSystemPrompt();
    final userPrompt = _buildTriageUserPrompt(input, includeImage: hasImage);

    if (kDebugMode) {
      final estTokens = ((systemPrompt.length + userPrompt.length) / 4).ceil();
      debugPrint(
        '[Aegis][LLM] generateReport begin '
        'sys=${systemPrompt.length}c user=${userPrompt.length}c '
        '~est=${estTokens}tok max=$maxTokens '
        'audio=${input.hasAudio} image=$hasImage '
        'visionDisabled=$_visionDisabled '
        'log=${input.incidentLog.length}',
      );
    }

    final sw = Stopwatch()..start();
    final chat = await model.createChat(
      // 0.7 / 40 / 0.9 keeps the model in a reasonable distribution. At
      // 0.3 we saw degenerate collapse onto repeated `<|"|>,<|"|>` escape
      // tokens inside `immediate_actions` — sampler kept picking the
      // same low-prob continuation. Slightly higher temp gives the
      // model enough room to commit to real action strings.
      temperature: 0.3,
      topK: 40,
      topP: 0.9,
      supportImage: hasImage,
      supportAudio: input.hasAudio,
      supportsFunctionCalls: true,
      tools: <Tool>[_renderTriageReportTool],
      // ToolChoice.required forces the model to emit a function call —
      // never plain prose. The whole point of this path is the
      // structured report.
      toolChoice: ToolChoice.required,
      modelType: ModelType.gemma4,
      // Thinking off for time-to-first-token. The fixed-schema tool
      // call gives us all the structure we need without burning
      // decode tokens on a reasoning chain.
      isThinking: false,
      systemInstruction: systemPrompt,
    );
    if (kDebugMode) {
      debugPrint(
        '[Aegis][LLM] generateReport chat created '
        'createMs=${sw.elapsedMilliseconds}',
      );
    }

    try {
      final message = Message(
        text: userPrompt,
        isUser: true,
        imageBytes: hasImage ? effectiveImage : null,
        audioBytes: input.hasAudio ? input.audioWav : null,
      );
      await chat.addQueryChunk(message);
      final genSw = Stopwatch()..start();
      // 12-minute hard cap. On low-end Mali devices with a cold
      // OpenCL context, the FIRST multimodal triage of the session
      // can spend 9+ minutes in `engine_create` + vision-encoder
      // prefill (one user reported 553 seconds). Subsequent turns in
      // the same session warm up to 10-30s. Cutting earlier than 12
      // minutes throws away a valid response — the Dart `.timeout`
      // can't cancel the running FFI call, so the native side runs
      // to completion regardless, and we'd just be losing the data
      // it produced.
      //
      // Anything beyond 12 minutes IS almost certainly a wedged
      // session (we have seen `EGL Production fence didn't signal`
      // loops hang the chat forever), so the cap stays — just
      // higher than before.
      final response = await chat.generateChatResponse().timeout(
        const Duration(minutes: 12),
        onTimeout: () {
          throw TimeoutException(
            'Triage analysis exceeded 12 minutes; native session likely '
            'wedged on GPU pipeline. Retry the request.',
          );
        },
      );
      if (kDebugMode) {
        debugPrint(
          '[Aegis][LLM] generateReport response '
          'kind=${response.runtimeType} '
          'elapsedMs=${genSw.elapsedMilliseconds}',
        );
      }
      final parsed = _parseToolResponse(response);
      if (parsed == null) return null;
      return _finaliseReport(parsed, capturedAt: capturedAt, gps: groundGps);
    } finally {
      try {
        await chat.close();
      } on Object {
        // best-effort
      }
    }
  }

  /// Stamp deterministic fields onto the model's tool output. The
  /// device already knows the timestamp and GPS — letting the model
  /// echo them just adds a hallucination surface (we saw dropped
  /// leading digits and mangled ISO strings). Also sanitizes
  /// `immediateActions` and clips obviously-truncated text.
  TriageReport _finaliseReport(
    TriageReport r, {
    required String capturedAt,
    required String gps,
  }) {
    // Filter action items, dropping JSON-fragment leakage that the
    // raw-fallback parser sometimes captures when Gemma 4's
    // `<|"|>…<|"|>` escape pairs get unbalanced inside the array
    // (e.g. items like `],severity:` or `summary:Flood inundation…`
    // smuggled from neighbouring keys).
    final leakedKey = RegExp(
      r'^\s*[\]\}]?\s*(?:severity|summary|format|title|hazard_type|'
      r'casualty_status|fema_scale|hazus_category|recommended_skill|'
      r'spoken_summary|body|prepared_at|prepared_by|gps)\s*:',
      caseSensitive: false,
    );
    final cleanedActions = <String>[];
    for (final raw in r.immediateActions) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length < 4) continue;
      // Pure punctuation / escape leakage.
      if (RegExp(r'^[\p{P}\p{S}\s]+$', unicode: true).hasMatch(trimmed)) {
        continue;
      }
      if (leakedKey.hasMatch(trimmed)) continue;
      // Reject items containing braces / brackets / unescaped quotes —
      // signs the parser stitched JSON syntax into the value.
      if (trimmed.contains(RegExp(r'[\{\}\[\]]'))) continue;
      cleanedActions.add(trimmed);
    }

    String trimTrailingGarbage(String s) {
      var out = s.trim();
      // Strip stray closing quote/curly tokens the model sometimes
      // appends when it runs out of decode budget mid-string.
      while (out.isNotEmpty &&
          (out.endsWith('"') ||
              out.endsWith("'") ||
              out.endsWith('“') ||
              out.endsWith('”'))) {
        out = out.substring(0, out.length - 1).trimRight();
      }
      // "…" ellipsis truncation marker → drop.
      out = out.replaceAll(RegExp(r'…+$'), '').trimRight();
      return out;
    }

    // Sometimes the decoder degenerates and tail-spams `render_report()`
    // / `render_triage_report()` over and over after the real call
    // closes. Trim everything from the first occurrence so it doesn't
    // leak into the body or summary.
    String stripDegenerateTail(String s) {
      final markers = <RegExp>[
        RegExp(r'render_(?:triage_)?report\s*\(', caseSensitive: false),
        RegExp(r'`{3,}', caseSensitive: false),
        RegExp(r'(?:_report){4,}', caseSensitive: false),
      ];
      var cut = s.length;
      for (final m in markers) {
        final hit = m.firstMatch(s);
        if (hit != null && hit.start < cut) cut = hit.start;
      }
      return cut == s.length ? s : s.substring(0, cut).trimRight();
    }

    // Severity must be one of the schema enum values. Empty / unknown
    // → derive a safe non-INFO default from hazardType so the card's
    // accent bar matches the analysis instead of looking benign.
    String normaliseSeverity(String raw) {
      const allowed = {'CRITICAL', 'HIGH', 'MODERATE', 'LOW', 'INFO'};
      final upper = raw.trim().toUpperCase();
      if (allowed.contains(upper)) return upper;
      return _severityFromHazard(r.hazardType);
    }

    final cleanedBody = trimTrailingGarbage(stripDegenerateTail(r.body));
    final cleanedTitle = trimTrailingGarbage(stripDegenerateTail(r.title));
    final cleanedSummary =
        trimTrailingGarbage(stripDegenerateTail(r.summary));

    return TriageReport(
      format: r.format,
      title: cleanedTitle.isEmpty
          ? _deriveTitle(r.hazardType, cleanedBody)
          : cleanedTitle,
      severity: normaliseSeverity(r.severity),
      summary: cleanedSummary.isEmpty
          ? _deriveSummary(cleanedBody)
          : cleanedSummary,
      body: cleanedBody,
      immediateActions: cleanedActions,
      // OVERRIDE: ground truth from device, not model.
      preparedAt: capturedAt,
      preparedBy: 'Aegis Triage Auto-Draft',
      hazardType: r.hazardType,
      hazusCategory: r.hazusCategory,
      femaScale: r.femaScale,
      damageDescription: r.damageDescription == null
          ? null
          : trimTrailingGarbage(stripDegenerateTail(r.damageDescription!)),
      casualtyStatus: r.casualtyStatus,
      casualtyCount: r.casualtyCount,
      casualtyTriageColor: r.casualtyTriageColor,
      // OVERRIDE: GPS comes from device sensor, not model.
      gps: gps.isEmpty ? null : gps,
      recommendedSkill: r.recommendedSkill,
      spokenSummary: r.spokenSummary == null
          ? null
          : trimTrailingGarbage(stripDegenerateTail(r.spokenSummary!)),
    );
  }

  /// Pick the first informative sentence from the body as a card
  /// subtitle. Used when the model omitted the `summary` field.
  static String _deriveSummary(String body) {
    if (body.isEmpty) return 'Triage report ready for review.';
    // Skip uppercase section headings; grab the first label-value or
    // narrative line.
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      // Heading line — all caps short — skip.
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.isNotEmpty &&
          letters == letters.toUpperCase() &&
          line.length < 32) {
        continue;
      }
      // Strip leading label `Foo:` if present.
      final colonIdx = line.indexOf(':');
      final value = colonIdx >= 0 && colonIdx < 24
          ? line.substring(colonIdx + 1).trim()
          : line;
      if (value.isEmpty) continue;
      // Cap at one sentence / 180 chars.
      final sentenceEnd = RegExp(r'[.!?]\s').firstMatch(value);
      final out = sentenceEnd != null
          ? value.substring(0, sentenceEnd.end - 1)
          : value;
      return out.length > 180 ? '${out.substring(0, 177)}…' : out;
    }
    return 'Triage report ready for review.';
  }

  /// Compose a title when the model omitted one. Falls back to the
  /// hazard label in Title Case.
  static String _deriveTitle(String? hazard, String body) {
    final h = hazard?.trim();
    if (h != null && h.isNotEmpty) {
      return h
          .replaceAll('_', ' ')
          .toLowerCase()
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }
    if (body.isEmpty) return 'Incident';
    return 'Incident';
  }

  /// Map hazard class to a safe severity default. Used when the model
  /// emitted an empty / invalid `severity` field. Bias toward higher
  /// severity so the responder sees the accent bar — emergency triage
  /// should never silently degrade to INFO.
  static String _severityFromHazard(String? hazard) {
    switch (hazard?.trim().toUpperCase()) {
      case 'CASUALTY':
      case 'MISSING_PERSON':
      case 'FIRE':
      case 'HAZMAT':
        return 'CRITICAL';
      case 'STRUCTURAL_DAMAGE':
      case 'FLOOD':
      case 'MEDICAL':
      case 'EVACUATION':
        return 'HIGH';
      default:
        return 'MODERATE';
    }
  }

  TriageReport? _parseToolResponse(ModelResponse response) {
    final List<FunctionCallResponse> calls = switch (response) {
      FunctionCallResponse() => <FunctionCallResponse>[response],
      ParallelFunctionCallResponse(:final calls) => calls,
      _ => const <FunctionCallResponse>[],
    };
    if (calls.isEmpty) {
      // SDK didn't surface a structured tool call. Try the raw token
      // fallback parser — flutter_gemma 0.15.0 occasionally returns
      // `<|tool_call>call:NAME{key:value,...}<tool_call|>` as text
      // content when the jinja template's reverse parse fails (seen
      // with multimodal input + Gemma 4 E2B).
      final rawText = response is TextResponse ? response.token : '';
      final fallbackArgs = _parseRawToolCall(rawText);
      if (fallbackArgs != null) {
        if (kDebugMode) {
          debugPrint(
            '[Aegis][LLM] generateReport raw-fallback parse OK '
            'keys=${fallbackArgs.keys.toList()}',
          );
        }
        return TriageReport.fromJson(fallbackArgs);
      }
      if (kDebugMode) {
        debugPrint(
          '[Aegis][LLM] generateReport NO tool call '
          'response=${rawText.length > 200 ? "${rawText.substring(0, 200)}…" : rawText}',
        );
      }
      return null;
    }
    // We declared exactly one tool with ToolChoice.required, but the
    // model can technically emit multiple. Pick the first
    // `render_triage_report` call and ignore the rest.
    FunctionCallResponse? picked;
    for (final call in calls) {
      if (call.name == _renderTriageReportTool.name) {
        picked = call;
        break;
      }
    }
    picked ??= calls.first;
    final args = _coerceArgs(picked.args);
    if (kDebugMode) {
      debugPrint(
        '[Aegis][LLM] generateReport tool=${picked.name} '
        'argKeys=${args.keys.toList()}',
      );
    }
    return TriageReport.fromJson(args);
  }

  /// Fallback parser for Gemma 4 raw `<|tool_call>call:NAME{...}<tool_call|>`
  /// text. The SDK's structured tool_calls extraction occasionally drops
  /// these calls (template reverse-parse miss) and surfaces them as
  /// plain text content. We walk the bare format ourselves so the report
  /// still lands.
  ///
  /// Format: `<|tool_call>call:render_triage_report{key:value,key:value,…}<tool_call|>`
  /// where value is one of:
  ///   * `<|"|>…<|"|>` — string (escape tokens both open AND close,
  ///     identical so we toggle on each occurrence)
  ///   * `[v,v,…]` — array
  ///   * `123` / `true` / `false` — int / bool
  Map<String, Object?>? _parseRawToolCall(String text) {
    const fenceStart = '<|tool_call>';
    const fenceEnd = '<tool_call|>';
    final startIdx = text.indexOf(fenceStart);
    if (startIdx < 0) return null;
    final endIdx = text.indexOf(fenceEnd, startIdx + fenceStart.length);
    final body = endIdx < 0
        ? text.substring(startIdx + fenceStart.length)
        : text.substring(startIdx + fenceStart.length, endIdx);

    // Expect "call:NAME{...".
    final callMatch = RegExp(r'^\s*call:([A-Za-z_][A-Za-z0-9_]*)\s*\{(.*)$',
            dotAll: true)
        .firstMatch(body);
    if (callMatch == null) return null;
    final name = callMatch.group(1)!;
    if (name != _renderTriageReportTool.name) return null;
    var payload = callMatch.group(2)!;
    // Trim trailing close brace if present.
    final closeIdx = _findMatchingClose(payload);
    if (closeIdx >= 0) payload = payload.substring(0, closeIdx);

    try {
      return _parseToolArgsBody(payload);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[Aegis][LLM] raw-fallback parse failed: $e');
      }
      return null;
    }
  }

  /// Find the index of the `}` that closes the outermost object — skips
  /// braces inside `<|"|>…<|"|>` quoted regions and inside `[…]`
  /// arrays.
  int _findMatchingClose(String s) {
    var depth = 1; // we already opened one
    var inString = false;
    const quote = '<|"|>';
    var i = 0;
    while (i < s.length) {
      if (s.startsWith(quote, i)) {
        inString = !inString;
        i += quote.length;
        continue;
      }
      final c = s[i];
      if (!inString) {
        if (c == '{' || c == '[') {
          depth++;
        } else if (c == '}' || c == ']') {
          depth--;
          if (depth == 0) return i;
        }
      }
      i++;
    }
    return -1;
  }

  /// Parse `key:value,key:value` into a map. Top-level only — nested
  /// `{...}` objects are not currently emitted by our tool schema.
  Map<String, Object?> _parseToolArgsBody(String body) {
    final out = <String, Object?>{};
    var i = 0;
    while (i < body.length) {
      // Skip whitespace and commas.
      while (i < body.length && (body[i] == ',' || body[i].trim().isEmpty)) {
        i++;
      }
      if (i >= body.length) break;
      // Read key up to `:`.
      final colonIdx = body.indexOf(':', i);
      if (colonIdx < 0) break;
      final key = body.substring(i, colonIdx).trim();
      i = colonIdx + 1;
      final (value, consumed) = _parseToolValue(body, i);
      out[key] = value;
      i = consumed;
    }
    return out;
  }

  /// Parse a single value starting at [start]. Returns the parsed value
  /// and the index just past the value.
  (Object?, int) _parseToolValue(String s, int start) {
    var i = start;
    // Skip whitespace.
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
    if (i >= s.length) return (null, i);
    const quote = '<|"|>';
    // String — opens with `<|"|>`.
    if (s.startsWith(quote, i)) {
      final close = s.indexOf(quote, i + quote.length);
      if (close < 0) {
        return (s.substring(i + quote.length).replaceAll(quote, ''), s.length);
      }
      final raw = s.substring(i + quote.length, close);
      return (raw.replaceAll(quote, ''), close + quote.length);
    }
    // Array.
    if (s[i] == '[') {
      final items = <Object?>[];
      i++;
      while (i < s.length) {
        while (i < s.length && (s[i] == ',' || s[i].trim().isEmpty)) {
          i++;
        }
        if (i < s.length && s[i] == ']') {
          return (items, i + 1);
        }
        final (item, next) = _parseToolValue(s, i);
        // Drop empty strings — Gemma sometimes pads arrays with `<|"|><|"|>`.
        if (item is String && item.trim().isEmpty) {
          i = next;
          continue;
        }
        items.add(item);
        i = next;
      }
      return (items, i);
    }
    // Bare token (int / bool / enum identifier). Read until comma /
    // brace / array close.
    final end = _scanBareTokenEnd(s, i);
    final raw = s.substring(i, end).trim();
    return (_coerceBareToken(raw), end);
  }

  int _scanBareTokenEnd(String s, int start) {
    var i = start;
    while (i < s.length) {
      final c = s[i];
      if (c == ',' || c == '}' || c == ']') break;
      i++;
    }
    return i;
  }

  Object? _coerceBareToken(String raw) {
    if (raw.isEmpty) return null;
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    if (raw == 'null') return null;
    return raw;
  }

  Map<String, Object?> _coerceArgs(Object? args) {
    if (args is Map<String, Object?>) return args;
    if (args is Map) {
      return args.map((k, v) => MapEntry(k.toString(), v));
    }
    if (args is String && args.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(args);
        if (decoded is Map<String, Object?>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } on FormatException catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[Aegis][LLM] generateReport args JSON decode failed: $e '
            'raw=${args.length > 200 ? "${args.substring(0, 200)}…" : args}',
          );
        }
      }
    }
    return const <String, Object?>{};
  }

  Future<String> _buildTriageSystemPrompt() async {
    final lang = _preferredLanguage;
    final langName = lang == null ? null : _languageNames[lang];
    final speakRule =
        langName == null ? 'Reply in the user\'s language.' : 'Reply in $langName.';

    // Tight system prompt. Tool schema carries all field rules; the
    // jinja-rendered tool declaration is already paying for the
    // OpenAI-Chat-Completions overhead — we keep this prompt under ~700
    // tokens so prefill + image patches stay tractable on Mali GPU.
    // Tight system prompt. Tool schema carries field shape; this
    // prompt carries DECISION rules (observe / infer / hedge) that
    // the schema can't express. Target ~250 tokens after chat-template
    // overhead so the bundle's `prefill_1024` ceiling has headroom
    // even after the tool jinja-render (~400-500 tokens). Earlier
    // version was double this size, hit DYNAMIC_UPDATE_SLICE on chunk
    // 2 because the KV cache slot allocator was sized for 1024 tokens.
    return '''
You are Aegis offline triage. $speakRule

Call `render_triage_report` ONCE per turn. No prose. No extra tool calls.

Decision rules:
1. OBSERVE — only count people, vehicles, structures, hazards you
   can actually SEE in the image or HEAR named in the audio/text.
2. CASUALTY DEFAULT: "0 reported" unless visible bodies / visible
   injured persons / explicit user statement ("3 trapped",
   "two hurt"). Do NOT estimate casualty counts from collapse
   footprint, damaged-roof area, or vehicle damage. Empty / unclear
   scene = "0 reported", NOT "~2 estimated".
3. STRUCTURE INFERENCE allowed: damage scale / HAZUS category /
   construction type can be inferred from visible damage with a
   hedge. People counts cannot.
4. If evidence is too thin to score (empty audio, blurry image,
   no user text), emit severity=INFO + summary="Insufficient
   evidence" and zero counts. Do not invent.

Never write GPS, lat/lng, timestamps — app injects them. Never emit
[INFERRED] / [UNKNOWN] / bracketed placeholders. Write a real value
with a hedge.

Skills for `recommended_skill`:
intake-survivor-statement (trapped/injured),
grade-damage-hazus (damage photo),
disaster-report-generator (SitRep/Flash/ICS-209),
plan-evacuation-route (route out),
compose-briefing (multi-incident),
match-mesh-beacon (missing person).
''';
  }

  static const int _incidentLogCharBudget = 1200;

  String _buildTriageUserPrompt(TriageInput input, {bool includeImage = true}) {
    final buf = StringBuffer();
    final user = input.userText.trim().isEmpty
        ? '(no spoken text — see attached evidence)'
        : input.userText.trim();
    buf.writeln('User: $user');

    // Deliberately omit raw GPS and capture timestamps from the prompt.
    // The app injects them post-tool-call from device sensors so the
    // model can't hallucinate or drop digits. Keeping them out of the
    // prompt also stops the model from echoing mangled copies inside
    // the body.
    final evidence = <String>[];
    if (input.hasAudio) evidence.add('audio attached');
    // Only advertise image evidence if the image actually reached the
    // chat session. Vision-circuit-breaker turns drop the image at the
    // service boundary, and lying to the model ("image attached" when
    // it wasn't) made the report invent visual details.
    if (input.hasImage && includeImage) evidence.add('image attached');
    if (input.gpsContext != null) evidence.add('gps fix present');
    if (evidence.isNotEmpty) buf.writeln('Evidence: ${evidence.join(', ')}');

    if (input.incidentLog.isNotEmpty) {
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
    if (input.requestId != null) buf.writeln('req_id: ${input.requestId}');
    return buf.toString();
  }

  Future<String> _askOnce(String userText, {required int maxTokens}) async {
    final chat = await _ensureChat(maxTokens: maxTokens);
    _logHistorySnapshot(chat, label: 'ask', incoming: userText);
    final wrapped = _buildUserTurnPrompt(userText);
    try {
      await chat.addQueryChunk(Message.text(text: wrapped, isUser: true));
      final response = await chat.generateChatResponse();
      final raw = response is TextResponse ? response.token : '';
      return _sanitizeFinalResponse(raw, userText: userText);
    } on Object {
      await _disposeChat();
      rethrow;
    } finally {
      // Multi-turn chat reuse on this bundle eventually segfaults inside
      // `libLiteRtLm.so::ThreadPool::RunWorker` (null deref during
      // second-turn prefill). Tear the chat down after every response
      // so each turn boots a fresh session — Dart-side `incidentLog`
      // still carries history into the next system prompt. Costs
      // ~3-5s of session create per turn; we trade speed for not
      // killing the entire process.
      await _disposeChat();
    }
  }

  Stream<ChatStreamEvent> _askStreamOnce(
    String userText, {
    required int maxTokens,
  }) async* {
    final chat = await _ensureChat(maxTokens: maxTokens);
    _logHistorySnapshot(chat, label: 'askStream', incoming: userText);
    final wrapped = _buildUserTurnPrompt(userText);
    try {
      await chat.addQueryChunk(Message.text(text: wrapped, isUser: true));

      // The mixed Stream<ModelResponse> interleaves text tokens and tool
      // calls. Split into two pipes:
      //   • text → _sanitizeStream (think-block + echo strip) → ChatTextChunk
      //   • FunctionCallResponse / ParallelFunctionCallResponse → ChatMapCall
      //
      // We use a broadcast controller + a relay coroutine because text
      // sanitisation needs an upstream Stream<String> not a per-event
      // callback.
      final textController = StreamController<String>();
      final mapEvents = <ChatMapCall>[];
      var relayDone = false;

      // Inline-tool-call detection state. Gemma 4 IT sometimes emits
      // the tool call as plain text (`render_map_view(...)`) instead
      // of the native `<|tool_call>` channel — observed on non-English
      // and Hinglish prompts after we trimmed the system prompt to
      // fit `prefill_1024`.
      //
      // Strategy: accumulate ALL output into [headBuffer] until we
      // can disambiguate. Three transitions:
      //   1. Buffer matches `render_map_view(` prefix → flip to
      //      [pythonCallSuppressed] mode, keep accumulating, parse
      //      when closing `)` arrives.
      //   2. Buffer grows past [_inlineCallProbeLimit] without
      //      matching → flush prefix to the chat-text stream and
      //      forward subsequent tokens directly. The model committed
      //      to prose; nothing to recover.
      //   3. Buffer is a strict-prefix of `render_map_view(` → keep
      //      holding (next token may complete the marker).
      final headBuffer = StringBuffer();
      var pythonCallSuppressed = false;
      var prefixDrained = false;

      void flushHeadAsText() {
        if (headBuffer.isEmpty) return;
        textController.add(headBuffer.toString());
        headBuffer.clear();
      }

      Future<void> relay() async {
        try {
          await for (final response
              in chat.generateChatResponseAsync()) {
            if (response is TextResponse) {
              final token = response.token;
              if (token.isEmpty) continue;
              // flutter_gemma 0.15.0 also emits the raw tool-call JSON
              // wrapper as a TextResponse *before* parsing it into a
              // FunctionCallResponse. Without this guard the JSON
              // blob (`{"role":"assistant","tool_calls":[...]}`) ends
              // up in the chat bubble next to the inline map card.
              if (_looksLikeToolCallJson(token)) continue;

              if (pythonCallSuppressed) {
                headBuffer.write(token);
                final parsed =
                    _tryParseInlinePythonCall(headBuffer.toString());
                if (parsed != null) {
                  if (kDebugMode) {
                    debugPrint(
                      '[Aegis][LLM] askStream inline-python tool=render_map_view '
                      'recovered (buffer=${headBuffer.length} chars)',
                    );
                  }
                  mapEvents.add(parsed);
                  headBuffer.clear();
                  pythonCallSuppressed = false;
                  prefixDrained = true;
                }
                continue;
              }

              if (prefixDrained) {
                textController.add(token);
                continue;
              }

              // Pre-disambiguation: keep accumulating without
              // emitting. We need ~`render_map_view(`.length chars
              // (16) to decide. Cap [_inlineCallProbeLimit] so a
              // model that opens with prose doesn't stall the chat
              // bubble forever.
              headBuffer.write(token);
              final head = headBuffer.toString();
              if (head.contains('render_map_view(')) {
                // Tool call detected — discard any preamble before
                // the marker (model occasionally prefixes whitespace
                // or quotes) and keep only the call itself.
                final markerIdx = head.indexOf('render_map_view(');
                headBuffer
                  ..clear()
                  ..write(head.substring(markerIdx));
                pythonCallSuppressed = true;
                // Try parse immediately in case the whole call
                // arrived in one chunk.
                final parsed =
                    _tryParseInlinePythonCall(headBuffer.toString());
                if (parsed != null) {
                  mapEvents.add(parsed);
                  headBuffer.clear();
                  pythonCallSuppressed = false;
                  prefixDrained = true;
                }
                continue;
              }

              // No marker yet. If buffer can no longer be a strict
              // prefix of `render_map_view(`, give up and flush to
              // chat stream.
              if (head.length >= _inlineCallProbeLimit ||
                  !_isPrefixOfRenderMapView(head)) {
                flushHeadAsText();
                prefixDrained = true;
              }
            } else if (response is FunctionCallResponse) {
              final call = _toMapCall(response);
              if (call != null) mapEvents.add(call);
            } else if (response is ParallelFunctionCallResponse) {
              for (final call in response.calls) {
                final mapped = _toMapCall(call);
                if (mapped != null) mapEvents.add(mapped);
              }
            }
          }
        } finally {
          // Flush any straggling buffered prelude. If we were in
          // suppression mode but never saw the closing `)`, treat
          // what we held as text — better to leak a broken
          // `render_map_view(` snippet than to drop the whole turn.
          if (!pythonCallSuppressed) flushHeadAsText();
          relayDone = true;
          await textController.close();
        }
      }

      unawaited(relay());

      await for (final chunk in _sanitizeStream(
        textController.stream,
        userText: userText,
      )) {
        yield ChatTextChunk(chunk);
        // Drain any tool calls that fired between text chunks so the UI
        // can paint the inline map as soon as Gemma commits to it.
        while (mapEvents.isNotEmpty) {
          yield mapEvents.removeAt(0);
        }
      }

      // Flush any tool calls that arrived after the last text chunk
      // (common when the model emits text then tool-call as the final
      // sequence, or skips text entirely).
      while (!relayDone) {
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      while (mapEvents.isNotEmpty) {
        yield mapEvents.removeAt(0);
      }
    } on Object {
      await _disposeChat();
      rethrow;
    } finally {
      // See ask() — same teardown for stability.
      await _disposeChat();
    }
  }

  /// True when [token] is the SDK's transitional emission of a tool
  /// call as text (a JSON envelope shaped like
  /// `{"role":"assistant","tool_calls":[…]}`). flutter_gemma 0.15.0
  /// emits this *and* a parsed `FunctionCallResponse` on the same
  /// stream — suppressing the text variant keeps the wrapper out of
  /// the chat bubble.
  static final RegExp _toolCallJsonProbe = RegExp(
    r'^\s*\{\s*"role"\s*:\s*"assistant".*"tool_calls"',
    multiLine: false,
    dotAll: true,
  );

  /// Max chars to hold before giving up on the inline-tool-call
  /// detection and forwarding text to the chat bubble. 64 chars is
  /// enough for any preamble + the 16-char `render_map_view(` marker
  /// while still being a hard upper bound on first-token latency.
  static const int _inlineCallProbeLimit = 64;
  static const String _renderMapMarker = 'render_map_view(';

  /// True when [text] could still grow into the `render_map_view(`
  /// marker via concatenation. Lets us hold off on flushing the
  /// buffer to the chat-text stream until we know the model isn't
  /// about to commit to a tool call.
  static bool _isPrefixOfRenderMapView(String text) {
    if (text.length >= _renderMapMarker.length) {
      return text.contains(_renderMapMarker);
    }
    return _renderMapMarker.startsWith(text);
  }

  bool _looksLikeToolCallJson(String token) {
    if (token.length < 32) return false;
    if (!token.contains('tool_calls')) return false;
    return _toolCallJsonProbe.hasMatch(token);
  }

  /// Fallback parser for the Python-style inline tool call
  /// `render_map_view(categories=["hospital"], radius_km=5,
  /// spoken_summary="…")` that Gemma 4 IT emits as plain text when it
  /// skips the native `<|tool_call>` channel — observed on non-English
  /// prompts after we trimmed the system prompt to fit `prefill_1024`.
  ///
  /// Returns a [ChatMapCall] when the buffer contains a complete,
  /// balanced call (closing `)` after a balanced argument list).
  /// Returns null while the call is still streaming so the caller can
  /// keep accumulating tokens.
  ChatMapCall? _tryParseInlinePythonCall(String buffer) {
    final openIdx = buffer.indexOf('render_map_view(');
    if (openIdx < 0) return null;
    final argsStart = openIdx + 'render_map_view('.length;
    // Walk forward respecting quoted strings + bracket nesting to find
    // the matching closing paren. Anything else inside is opaque.
    var depth = 1;
    var i = argsStart;
    var inString = false;
    var escape = false;
    while (i < buffer.length) {
      final ch = buffer[i];
      if (escape) {
        escape = false;
      } else if (ch == '\\') {
        escape = true;
      } else if (ch == '"') {
        inString = !inString;
      } else if (!inString) {
        if (ch == '(' || ch == '[' || ch == '{') {
          depth++;
        } else if (ch == ')' || ch == ']' || ch == '}') {
          depth--;
          if (depth == 0 && ch == ')') {
            return _coerceInlineArgs(buffer.substring(argsStart, i));
          }
        }
      }
      i++;
    }
    return null;
  }

  /// Pull keyword arguments out of a Python-style call body
  /// (`categories=["hospital"], radius_km=5, spoken_summary="..."`).
  /// Best-effort — produces empty / partial maps gracefully when
  /// values are malformed rather than throwing, because tool-call
  /// recovery on a flaky stream is better than nothing.
  ChatMapCall? _coerceInlineArgs(String body) {
    final args = <String, Object?>{};
    final keyRe =
        RegExp(r'(\w+)\s*=', multiLine: true);
    final matches = keyRe.allMatches(body).toList();
    for (var m = 0; m < matches.length; m++) {
      final keyMatch = matches[m];
      final key = keyMatch.group(1);
      if (key == null) continue;
      final valueStart = keyMatch.end;
      final valueEnd =
          m + 1 < matches.length ? matches[m + 1].start : body.length;
      final raw = body.substring(valueStart, valueEnd).trim();
      args[key] = _parseInlineValue(raw);
    }
    if (args.isEmpty) return null;
    return ChatMapCall(MapViewQuery.fromArgs(args));
  }

  /// Decode a single Python-style value (quoted string, JSON array,
  /// or bare number). Strips trailing commas. Conservative — anything
  /// it can't decode comes back as the raw trimmed string.
  Object? _parseInlineValue(String raw) {
    var s = raw.trim();
    if (s.endsWith(',')) s = s.substring(0, s.length - 1).trim();
    if (s.isEmpty) return null;
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      return s.substring(1, s.length - 1);
    }
    if (s.startsWith('[') && s.endsWith(']')) {
      // Tiny array decoder: split on commas, unwrap quoted strings.
      final inner = s.substring(1, s.length - 1);
      final parts = <String>[];
      var buf = StringBuffer();
      var inStr = false;
      var esc = false;
      for (final ch in inner.split('')) {
        if (esc) {
          buf.write(ch);
          esc = false;
        } else if (ch == '\\') {
          esc = true;
        } else if (ch == '"') {
          inStr = !inStr;
        } else if (ch == ',' && !inStr) {
          parts.add(buf.toString());
          buf = StringBuffer();
        } else {
          buf.write(ch);
        }
      }
      if (buf.isNotEmpty) parts.add(buf.toString());
      return parts
          .map((p) {
            final t = p.trim();
            if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
              return t.substring(1, t.length - 1);
            }
            return t;
          })
          .where((p) => p.isNotEmpty)
          .toList();
    }
    final asNum = num.tryParse(s);
    if (asNum != null) return asNum;
    return s;
  }

  /// Convert a flutter_gemma `FunctionCallResponse` into a [ChatMapCall]
  /// when its name matches the chat-path tool. Returns null for unknown
  /// tools so the cubit can ignore them safely.
  ChatMapCall? _toMapCall(FunctionCallResponse response) {
    if (response.name != _renderMapViewTool.name) return null;
    final args = _coerceArgs(response.args);
    if (kDebugMode) {
      debugPrint(
        '[Aegis][LLM] askStream tool=${response.name} '
        'argKeys=${args.keys.toList()}',
      );
    }
    return ChatMapCall(MapViewQuery.fromArgs(args));
  }

  String _buildUserTurnPrompt(String userText) {
    final input = userText.trim();
    final scriptCode = _detectLanguageFromScript(input);
    final code = scriptCode ?? _preferredLanguage;
    final name = code == null ? null : _languageNames[code];
    final languageLine = name == null
        ? 'Reply in the user\'s script.'
        : 'Reply in $name (native script).';

    // Tool-trigger nudge for non-English queries. Gemma 4 IT's
    // `render_map_view` recall drops on non-English prompts; appending
    // an explicit hint when the user clearly asks for nearby places
    // pushes recall back up without spending the prompt budget on
    // every turn.
    final nearbyHint = _hasNearbyPlacesIntent(input)
        ? '\n- Nearby-places query → call `render_map_view`. No location prompt.'
        : '';

    return '''User: $input
- Direct answer, no quoting the user.
- $languageLine$nearbyHint
''';
  }

  /// Heuristic: does the user's message read like a "find nearby X"
  /// query? Lowercased substring match against multilingual keywords
  /// for the categories `render_map_view` covers. Catches the most
  /// common phrasings without a full NLU pass — false positives only
  /// result in an extra hint to the model, which is harmless. False
  /// negatives are silent; the system prompt's NEARBY-PLACES RULE
  /// still fires the tool in those cases.
  ///
  /// Coverage spans Aegis's 12 priority locales (en, hi, bn, ta, te,
  /// mr, gu, pa, ur, es, ar, zh). Other languages fall back entirely
  /// on the system prompt rule + tool description.
  static const List<String> _nearbyIntentTokens = <String>[
    // -- English --
    'nearby', 'nearest', 'closest', 'find', 'show', 'where',
    'hospital', 'clinic', 'pharmacy', 'shelter', 'fuel', 'gas station',
    'fuel station', 'water', 'food', 'atm', 'police', 'fire station',
    'charging', 'wifi',
    // -- Hindi (हिन्दी) --
    // Cover both nuktaless (नजदीक) and nukta (नज़दीक) variants since
    // users type both. Same for हॉस्पिटल vs अस्पताल (Latin-loan vs
    // pure-Hindi).
    'नज़दीक', 'नज़दीकी', 'नजदीक', 'नजदीकी', 'पास', 'कहाँ', 'किधर',
    'ढूँढो', 'ढूंढो', 'ढूँढ', 'ढूंढ', 'खोजो', 'खोज',
    'अस्पताल', 'हॉस्पिटल', 'हास्पिटल', 'क्लिनिक', 'दवाई', 'फार्मेसी',
    'आश्रय', 'शेल्टर', 'पानी', 'जल', 'पुलिस', 'एटीएम',
    'ईंधन', 'फ्यूल', 'पेट्रोल', 'खाना', 'भोजन',
    // -- Bengali (বাংলা) --
    'কাছাকাছি', 'কাছে', 'নিকটতম', 'কোথায়', 'খুঁজে',
    'হাসপাতাল', 'ক্লিনিক', 'ওষুধ', 'আশ্রয়', 'পানি', 'জল',
    'পুলিশ', 'এটিএম', 'জ্বালানি', 'খাবার',
    // -- Tamil (தமிழ்) --
    'அருகில்', 'நெருங்கிய', 'எங்கே', 'கண்டுபிடி',
    'மருத்துவமனை', 'மருந்தகம்', 'தங்குமிடம்', 'தண்ணீர்',
    'காவல்', 'எரிபொருள்', 'உணவு',
    // -- Telugu (తెలుగు) --
    'దగ్గర', 'సమీప', 'ఎక్కడ', 'కనుగొనండి',
    'ఆసుపత్రి', 'క్లినిక్', 'ఔషధశాల', 'ఆశ్రయం', 'నీరు',
    'పోలీసు', 'ఇంధనం', 'ఆహారం',
    // -- Marathi (मराठी) --
    'जवळ', 'जवळचा', 'जवळचे', 'कुठे', 'शोधा',
    'रुग्णालय', 'दवाखाना', 'आश्रय', 'पाणी', 'पोलीस', 'इंधन', 'अन्न',
    // -- Gujarati (ગુજરાતી) --
    'નજીક', 'નજીકના', 'ક્યાં', 'શોધો',
    'હોસ્પિટલ', 'દવાખાનું', 'આશ્રય', 'પાણી', 'પોલીસ', 'ઈંધણ',
    // -- Punjabi (ਪੰਜਾਬੀ) --
    'ਨੇੜੇ', 'ਨੇੜਲਾ', 'ਕਿੱਥੇ', 'ਲੱਭੋ',
    'ਹਸਪਤਾਲ', 'ਕਲੀਨਿਕ', 'ਆਸਰਾ', 'ਪਾਣੀ', 'ਪੁਲਿਸ', 'ਬਾਲਣ',
    // -- Urdu (اردو) --
    'قریب', 'قریبی', 'کہاں', 'تلاش',
    'ہسپتال', 'کلینک', 'پناہ', 'پانی', 'پولیس', 'ایندھن', 'کھانا',
    // -- Spanish (Español) --
    'cerca', 'cercano', 'cercana', 'más cercano', 'dónde', 'donde',
    'buscar', 'encontrar', 'hospital', 'clínica', 'farmacia', 'refugio',
    'agua', 'policía', 'gasolinera', 'combustible', 'comida',
    // -- Arabic (العربية) --
    'قريب', 'الأقرب', 'أين', 'ابحث', 'مستشفى', 'عيادة', 'صيدلية',
    'ملجأ', 'ماء', 'شرطة', 'وقود', 'طعام',
    // -- Chinese (中文) --
    '附近', '最近', '哪里', '哪裡', '找',
    '医院', '醫院', '诊所', '診所', '药房', '藥房', '避难所', '避難所',
    '水', '警察', '加油站', '食物',
  ];

  bool _hasNearbyPlacesIntent(String text) {
    final lower = text.toLowerCase();
    for (final tok in _nearbyIntentTokens) {
      if (lower.contains(tok.toLowerCase())) return true;
    }
    return false;
  }

  String? _detectLanguageFromScript(String text) {
    if (text.isEmpty) return null;
    final counts = <String, int>{};
    for (final rune in text.runes) {
      final s = _scriptForRune(rune);
      if (s == null) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final dominant =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    if (dominant == 'latin') {
      // Latin script is ambiguous (en, es, pt, fr, de, vi, sw, ...).
      // When the persisted locale uses a non-Latin script (hi/bn/ta/
      // etc.), the user typing Latin means they switched to English
      // for this turn — return `en` so the reply doesn't come back
      // in Devanagari. When persisted locale is already Latin-native
      // (en, es, pt, fr, de, it, etc.), respect it.
      final pref = _preferredLanguage;
      if (pref == null || _latinNativeLocales.contains(pref)) {
        return pref;
      }
      return 'en';
    }
    return _scriptToLanguageHint[dominant];
  }

  /// Locales whose dominant script is Latin. Used by
  /// [_detectLanguageFromScript] to decide whether Latin-script input
  /// implies an English switch or just normal typing in the user's
  /// preferred Latin-script locale.
  static const Set<String> _latinNativeLocales = <String>{
    'en', 'es', 'pt', 'fr', 'de', 'it', 'nl', 'sv', 'no', 'da', 'fi',
    'pl', 'cs', 'sk', 'hu', 'ro', 'tr', 'vi', 'id', 'ms', 'tl', 'sw',
    'ha', 'yo', 'af', 'sq', 'hr', 'sl', 'lt', 'lv', 'et', 'is', 'ga',
    'cy', 'eu', 'ca', 'gl', 'mt', 'lb',
  };

  static String? _scriptForRune(int rune) {
    // Basic Latin (A-Z, a-z) and Latin-1 Supplement letters. Excludes
    // ASCII whitespace, punctuation, digits — those don't tell us
    // anything about the message language.
    if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x00C0 && rune <= 0x00FF)) {
      return 'latin';
    }
    if (rune >= 0x0900 && rune <= 0x097F) return 'devanagari';
    if (rune >= 0x0980 && rune <= 0x09FF) return 'bengali';
    if (rune >= 0x0A00 && rune <= 0x0A7F) return 'gurmukhi';
    if (rune >= 0x0A80 && rune <= 0x0AFF) return 'gujarati';
    if (rune >= 0x0B80 && rune <= 0x0BFF) return 'tamil';
    if (rune >= 0x0C00 && rune <= 0x0C7F) return 'telugu';
    if (rune >= 0x0C80 && rune <= 0x0CFF) return 'kannada';
    if (rune >= 0x0D00 && rune <= 0x0D7F) return 'malayalam';
    if (rune >= 0x0600 && rune <= 0x06FF) return 'arabic';
    if (rune >= 0x0400 && rune <= 0x04FF) return 'cyrillic';
    if (rune >= 0x0E00 && rune <= 0x0E7F) return 'thai';
    if (rune >= 0x4E00 && rune <= 0x9FFF) return 'cjk';
    if (rune >= 0x3040 && rune <= 0x30FF) return 'kana';
    if (rune >= 0xAC00 && rune <= 0xD7AF) return 'hangul';
    return null;
  }

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

  Future<InferenceChat> _ensureChat({required int maxTokens}) async {
    final cached = _chat;
    if (cached != null) return cached;
    final model = await _ensureModel(maxTokens: maxTokens);
    final chat = await model.createChat(
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
      // Agentic chat: expose `render_map_view` so Gemma 4 can pin an
      // inline map onto the turn when the user asks about nearby
      // shelters / hospitals / water / etc. ToolChoice.auto means the
      // model can still emit plain text for non-places turns. Triage
      // uses its own one-shot session with `render_triage_report` so
      // the two surfaces never collide.
      supportsFunctionCalls: true,
      tools: <Tool>[_renderMapViewTool],
      toolChoice: ToolChoice.auto,
      isThinking: false,
      modelType: ModelType.gemma4,
      systemInstruction: _buildSystemPrompt(
        _preferredLanguage,
        briefingContext: _briefingContext,
      ),
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
  /// [useChat]. No-op if the active pack is missing or not
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
      // We MUST decode at least one token here, not just create the
      // session. Engine init + session create only loads weights — the
      // first decode is what triggers OpenCL/WebGPU shader compilation
      // (10–15 s on real Adreno/Mali) and the first KV-cache prefill on
      // the GPU memory allocator. Without that, the first real alert
      // routing call still pays the full cold-start tax (observed:
      // 15 s prefill + 20 s decode = 35 s, exceeding the AlertRouter
      // watchdog and dismissing real emergencies). Run the decode
      // serialised through [_oneShotChain] so we don't race a real
      // routing call.
      _oneShotChain = _oneShotChain
          .catchError((Object _, StackTrace _) {})
          .then((_) async {
            // CRITICAL: pass the SAME engine maxTokens the router uses
            // (1024) so warm-up doesn't lock the cached engine at a
            // small ceiling. [_ensureModel] keys cache by maxTokens —
            // a tiny warm-up value (e.g. 8) would build an 8-token
            // engine, then the next real alert (524-token prompt)
            // throws "Input token ids are too long" because the
            // engine was sized for 8.
            final raw = await _oneShotWithFallback(
              systemInstruction: '',
              userPrompt: 'OK',
              maxTokens: maxTokens,
              temperature: temperature,
              topK: topK,
              topP: topP,
            );
            if (kDebugMode) {
              debugPrint(
                '[LlmService] warm-up decode produced ${raw.length} chars',
              );
            }
          });
      await _oneShotChain;
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
        // best-effort
      }
    }
  }

  String _sanitizeFinalResponse(String response, {String? userText}) {
    final withoutThinking = response.replaceAll(_thinkBlockRegex, '');
    final cleaned = withoutThinking.replaceAll(_reservedToken, '').trim();
    return _stripLeadingEcho(cleaned, userText: userText);
  }

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
            break;
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

    if (normalize(cleaned) == normalizedUser ||
        normalize(cleaned.replaceAll(_leadingQuote, '')) == normalizedUser) {
      return '';
    }
    return cleaned.trim();
  }

  /// Recovery predicate for transient GPU / vision-decode crashes.
  /// We do NOT flip to CPU on this bundle — its CPU path is fatally
  /// broken (XNNPack rejects `DYNAMIC_UPDATE_SLICE` at node 1164 at
  /// delegate-prepare time, so prefill never starts on CPU). The only
  /// usable backend is GPU. Recovery here:
  ///   1. Dispose the engine so the next call rebuilds a clean session
  ///      (avoids stale OpenCL buffer state poisoning the retry).
  ///   2. Flip + persist `_visionDisabled` when the crash carried a
  ///      vision / tensor-buffer signature (the image is what
  ///      poisoned the GPU; future turns must skip it).
  ///   3. Return true so the caller retries the SAME backend with
  ///      vision stripped.
  /// Returns false on the original "OpenCL shared lib totally missing"
  /// case — that's a hard hardware failure; the caller should give up
  /// rather than loop on a CPU path that doesn't work either.
  Future<bool> _shouldFallbackToCpu(Object error) async {
    if (!_isOpenClUnavailable(error)) return false;
    final lower = error.toString().toLowerCase();
    final samplerDlopen = lower.contains('libliterttopkopenclsampler') ||
        lower.contains('libliterttopkwebgpusampler');
    if (samplerDlopen) {
      // Sampler shared lib missing entirely → no usable backend on
      // this bundle. Don't pretend a CPU retry will help — just
      // bubble up so the cubit surfaces a clean error.
      if (kDebugMode) {
        debugPrint(
          '[Aegis][LLM] sampler shared lib missing; not retrying — '
          'CPU path is XNNPack-incompatible on this bundle',
        );
      }
      return false;
    }

    final visionSignature = lower.contains('convert_tensor_buffer') ||
        lower.contains('litert_tensor_buffer') ||
        lower.contains('llm_litert_compiled_model_executor') ||
        lower.contains('clenqueuemapbuffer') ||
        lower.contains('clenqueuewritebuffer') ||
        lower.contains('stablehlo_composite') ||
        lower.contains('dynamic_update_slice') ||
        lower.contains('failed to allocate tensors');
    if (visionSignature && !_visionDisabled) {
      _visionDisabled = true;
    }
    await _disposeModel();
    final store = _hardwareStore;
    if (store != null && visionSignature) {
      try {
        await store.persistDisableVision();
        if (kDebugMode) {
          debugPrint(
            '[Aegis][LLM] persisted disableVision=true after GPU '
            'tensor-buffer / KV-cache failure',
          );
        }
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint('[Aegis][LLM] persistDisableVision failed: $e');
        }
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[Aegis][LLM] GPU delegate failure — disposed engine, '
        'visionDisabled=$_visionDisabled, retrying same GPU backend',
      );
    }
    return true;
  }

  Future<void> dispose() async {
    await _disposeModel();
    _installed = false;
    _loadFuture = null;
  }

  Future<InferenceModel> _ensureModel({required int maxTokens}) async {
    final pack = _activePack;
    if (pack == null) {
      throw StateError(
        'LlmService used before setChatPack — call useChat() (or the '
        'legacy setPack) first',
      );
    }
    if (!await _registry.isInstalled(pack)) {
      throw StateError('LLM pack ${pack.id} is not installed');
    }

    // Engine `max_num_tokens` ceiling is BIGGER-IS-FINE — bumping a
    // chat path that only needs 1024 onto a 4096-token engine costs us
    // nothing (the ceiling only matters for triage's vision prefill).
    // So when paths disagree, we always satisfy the LARGEST request
    // and reuse a single engine across ASR / chat / triage. This kills
    // the "ASR loads 1024 → triage requests 4096 → race returns the
    // 1024 engine → INVALID_ARGUMENT: 2263 >= 1024" bug.
    final effective =
        _model != null && _model!.maxTokens > maxTokens
            ? _model!.maxTokens
            : maxTokens;
    final cached = _model;
    if (cached != null && cached.maxTokens >= effective) return cached;

    final existingLoad = _loadFuture;
    if (existingLoad != null) {
      await existingLoad;
      final reloaded = _model;
      // BUG FIX: previously returned `reloaded` unconditionally — if
      // the in-flight load was a smaller-capacity engine (e.g. ASR's
      // 1024), the caller asking for 4096 silently got the 1024
      // engine and image prefill blew up at the JNI boundary. Now we
      // only return when the awaited engine actually has the ceiling
      // we need; otherwise fall through to rebuild.
      if (reloaded != null && reloaded.maxTokens >= effective) {
        return reloaded;
      }
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
        // Use the larger ceiling (see `effective` calc above) so we
        // never recreate the engine just because a chat turn asked
        // for a smaller cap than a previous triage turn.
        maxTokens: effective,
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
    // Original signals: sampler shared lib missing entirely.
    if (message.contains('opencl') ||
        message.contains('libliterttopkopenclsampler')) {
      return true;
    }
    // Additional GPU-delegate failure modes observed on Mali devices
    // where the OpenCL runtime is present but in a bad state — usually
    // after a prior session left GPU context dirty, or the driver
    // rejected the kernel batch. Force-fall to CPU so the next attempt
    // doesn't loop on the same broken delegate.
    //
    // NB: `convert_tensor_buffer` / `litert_tensor_buffer` / the
    // `llm_litert_compiled_model_executor` runtime errors are ALSO
    // GPU-side corruption signatures even when the model object is
    // text-only at the Dart layer — the underlying engine's KV cache
    // and prefill buffers live on the same poisoned OpenCL context.
    // Catching them here means [_shouldFallbackToCpu] dominates over
    // [_shouldFallbackToTextOnly] in the `generateReport` chain, so
    // the engine actually rebuilds on CPU instead of retrying
    // text-only on the same broken GPU handle.
    return message.contains('clenqueuewritebuffer') ||
        message.contains('clenqueuemapbuffer') ||
        message.contains('failed to upload data to gpu') ||
        message.contains('delegatekernellitert') ||
        message.contains('stablehlo_composite') ||
        message.contains('dynamic_update_slice') ||
        message.contains('failed to create engine') ||
        message.contains('failed to initialize kernel') ||
        message.contains('convert_tensor_buffer') ||
        message.contains('litert_tensor_buffer') ||
        message.contains('llm_litert_compiled_model_executor');
  }

  Future<void> _install(VoiceModelPack pack) async {
    if (_installed) return;
    final path = await _registry.absolutePath(pack, pack.modelFile);
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
    _installed = true;
  }

  Future<void> _disposeModel() async {
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
