import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:genui/genui.dart' as genui;

import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/model_catalog.dart';
import '../../../core/voice/model_pack.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/triage_input.dart';
import '../../../core/voice/tts_service.dart';
import '../widgets/aegis_catalog.dart';

part 'assistant_cubit.freezed.dart';

/// One completed back-and-forth in a conversation. Appended to
/// [AssistantState.turns] when the model finishes responding to a turn so
/// the UI can render the running history (the previous transcript/response
/// pair otherwise gets clobbered the moment the next utterance starts).
@immutable
class ConversationTurn {
  const ConversationTurn({
    required this.user,
    required this.assistant,
    this.hadSurface = false,
  });

  final String user;
  final String assistant;

  /// True when the agent emitted an A2UI surface for this turn (eg. a
  /// triage / capture-evidence prompt). Past turns don't keep a frozen
  /// snapshot of the surface — the home view shows a marker chip
  /// instead. The live surface always reflects the most recent turn.
  final bool hadSurface;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationTurn &&
          other.user == user &&
          other.assistant == assistant &&
          other.hadSurface == hadSurface;

  @override
  int get hashCode => Object.hash(user, assistant, hadSurface);

  @override
  String toString() =>
      'ConversationTurn(user: $user, assistant: $assistant, hadSurface: $hadSurface)';
}

/// Stage of the assistant pipeline. The UI reacts to each one: the mic
/// button pulses on `listening`, the transcript bubble fades in on
/// `transcribing`, Aegis speaks on `speaking`, etc.
enum AssistantStage {
  idle,
  preparing,
  listening,
  transcribing,
  thinking,
  speaking,
  awaitingConfirmation,
  degraded, // Voice disabled (no model pack installed)
  error,
}

@freezed
abstract class AssistantState with _$AssistantState {
  const factory AssistantState({
    @Default(AssistantStage.idle) AssistantStage stage,
    @Default('') String transcript,
    @Default('') String response,
    @Default(<ConversationTurn>[]) List<ConversationTurn> turns,
    @Default(false) bool surfaceReady,
    @Default('') String thinkingTrace,
    String? errorMessage,
  }) = _AssistantState;

  const AssistantState._();

  bool get isBusy =>
      stage == AssistantStage.preparing ||
      stage == AssistantStage.listening ||
      stage == AssistantStage.transcribing ||
      stage == AssistantStage.thinking ||
      stage == AssistantStage.speaking ||
      stage == AssistantStage.awaitingConfirmation;

  /// True when the cubit is in the middle of an active conversation —
  /// regardless of which sub-stage (listening / thinking / speaking).
  /// The UI uses this to render a "stop conversation" affordance.
  bool get isConversationActive =>
      stage == AssistantStage.listening ||
      stage == AssistantStage.transcribing ||
      stage == AssistantStage.thinking ||
      stage == AssistantStage.speaking ||
      stage == AssistantStage.awaitingConfirmation;
}

/// Orchestrates the offline assistant pipeline:
///   mic → STT → LLM (genui-aware triageStream) → TTS + live A2UI surface.
///
/// One **conversation** can contain many turns. Every turn flows through
/// the same pipeline — the agent decides whether to emit a generated
/// surface (triage report, capture-evidence prompt, etc.) or to keep
/// the reply purely conversational. From the cubit's perspective, both
/// modes share the same code path: the genui transport routes JSON
/// envelopes to the surface controller and the leftover prose to TTS.
///
/// Verification chrome (Confirm / Reject) only appears when the agent
/// emits a `ConfirmActionBar` inside the surface. A purely text reply
/// commits straight to history and the mic re-opens.
class AssistantCubit extends Cubit<AssistantState> {
  AssistantCubit({
    required AudioRecorderService recorder,
    required SttService stt,
    required LlmService llm,
    required TtsService tts,
    required String countryCode,
    String? languageCode,
  })  : _recorder = recorder,
        _stt = stt,
        _llm = llm,
        _tts = tts,
        _countryCode = countryCode,
        _languageCode = languageCode,
        _catalog = buildAegisCatalog(),
        super(const AssistantState()) {
    _surfaceController = genui.SurfaceController(catalogs: [_catalog]);
    _actionSub = _surfaceController.onSubmit.listen(_onSurfaceSubmit);
    _llm.setTriageCatalog(_catalog);
    _bootstrap();
  }

  static const String surfaceId = 'aegis-home';

  /// Cap on prior turns we replay into the per-turn `incidentLog`.
  /// Each turn ≈ 100-300 tokens of summarised history; 4 entries
  /// keeps replay under ~1.2k tokens which fits inside Gemma 4
  /// E2B's tight context window with room for the system prompt and
  /// the model's reply. The full chat history is still rendered in
  /// the UI.
  static const int _historyTurnsForReplay = 4;

  final AudioRecorderService _recorder;
  final SttService _stt;
  final LlmService _llm;
  final TtsService _tts;
  final String _countryCode;
  final String? _languageCode;
  final genui.Catalog _catalog;

  late final genui.SurfaceController _surfaceController;
  late final StreamSubscription<genui.ChatMessage> _actionSub;

  StreamSubscription<SttUpdate>? _sttSub;
  StreamSubscription<String>? _llmSub;
  StreamSubscription<dynamic>? _surfaceUpdatesSub;
  Timer? _autoConfirmTimer;
  genui.A2uiTransportAdapter? _transport;
  bool _voiceReady = false;
  bool _conversationActive = false;

  /// Exposed to the home view so the [genui.Surface] widget can bind
  /// to the cubit's controller via `contextFor(surfaceId)`.
  genui.SurfaceController get surfaceController => _surfaceController;

  Future<void> _bootstrap() async {
    emit(state.copyWith(stage: AssistantStage.preparing));
    try {
      final plan = ModelCatalog.planFor(_countryCode);
      // Pick packs that match the user's selected language, not just the
      // first pack in the region plan. India's plan, for example, lists the
      // Hindi voice first, but a user who picked English would otherwise
      // hear the Hindi voice trying to phonemize English text — sounds
      // foreign / wrong. The same applies to the streaming-vs-Whisper STT
      // pick: Hindi speakers should land on Whisper-multilingual instead of
      // the English-only Zipformer.
      final ttsPacks = _orderedTtsPacks(plan.tts, _languageCode);
      // VAD is global / language-agnostic: always pick the first pack.
      final vad = plan.vad.isNotEmpty ? plan.vad.first : null;
      final llm = plan.llm.isNotEmpty ? plan.llm.first : null;

      if (ttsPacks.isNotEmpty) _tts.loadAll(ttsPacks).ignore();
      if (vad != null) _stt.setVadPack(vad);
      if (llm != null) {
        _llm.setPack(llm);
        _llm.setPreferredLanguage(_languageCode);
      }

      final sttOk = vad != null && await _stt.isAvailable();
      final llmOk = llm != null && await _llm.isAvailable();

      if (!sttOk || !llmOk) {
        emit(state.copyWith(stage: AssistantStage.degraded));
        return;
      }

      _voiceReady = true;
      emit(state.copyWith(stage: AssistantStage.idle));
    } on Object catch (e) {
      emit(
        state.copyWith(
          stage: AssistantStage.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> toggleConversation() async {
    if (_conversationActive) {
      await stopConversation();
    } else {
      await startConversation();
    }
  }

  Future<void> startConversation() async {
    if (!_voiceReady) return;
    if (_conversationActive) return;
    _conversationActive = true;
    emit(
      state.copyWith(
        transcript: '',
        response: '',
        turns: const <ConversationTurn>[],
        surfaceReady: false,
        thinkingTrace: '',
        errorMessage: null,
      ),
    );
    unawaited(_llm.resetSession());
    unawaited(_runListenLoop());
  }

  Future<void> stopConversation() async {
    _conversationActive = false;
    _autoConfirmTimer?.cancel();
    await _sttSub?.cancel();
    _sttSub = null;
    await _llmSub?.cancel();
    _llmSub = null;
    await _surfaceUpdatesSub?.cancel();
    _surfaceUpdatesSub = null;
    _transport?.dispose();
    _transport = null;
    try {
      await _recorder.cancel();
    } on Object {
      // best-effort
    }
    await _tts.stop();
    if (state.stage != AssistantStage.degraded &&
        state.stage != AssistantStage.error) {
      emit(state.copyWith(stage: AssistantStage.idle, surfaceReady: false));
    }
  }

  Future<void> startListening() => startConversation();
  Future<void> stopAndAsk() => stopConversation();
  Future<void> cancel() => stopConversation();

  /// Type-driven ask — bypasses the mic loop. Used when the user
  /// prefers typing (low-bandwidth scenarios, accessibility profiles
  /// that rely on text input).
  Future<void> submitTyped(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!_voiceReady) return;
    _conversationActive = true;
    await _respondTo(trimmed);
    _conversationActive = false;
  }

  /// Confirms the currently displayed surface — fired either by the
  /// auto-confirm timer (Ask-style turns) or by the agent-emitted
  /// `ConfirmActionBar`. Clears the surface and re-opens the mic if
  /// the conversation is still active.
  Future<void> confirmSurface() async {
    if (state.stage != AssistantStage.awaitingConfirmation) return;
    _autoConfirmTimer?.cancel();
    emit(state.copyWith(stage: AssistantStage.idle, surfaceReady: false));
    if (_conversationActive) {
      unawaited(_runListenLoop());
    }
  }

  /// Rejects the currently displayed surface. Re-asks the model with a
  /// correction note appended to the incident log so the next pass has
  /// the user's feedback. Only meaningful if the previous turn left a
  /// surface up.
  Future<void> rejectSurface({String? correction}) async {
    if (state.stage != AssistantStage.awaitingConfirmation) return;
    final last = state.turns.isEmpty ? null : state.turns.last;
    final userText = last?.user;
    if (userText == null || userText.isEmpty) {
      emit(state.copyWith(stage: AssistantStage.idle, surfaceReady: false));
      return;
    }
    _autoConfirmTimer?.cancel();
    await _tts.stop();

    // Drop the rejected turn from history so the corrected retry
    // takes its place, then re-run the LLM with a feedback note.
    final priorTurns = state.turns.sublist(0, state.turns.length - 1);
    emit(state.copyWith(
      turns: List.unmodifiable(priorTurns),
      surfaceReady: false,
      thinkingTrace: '',
    ));
    await _respondTo(
      userText,
      extraIncidentLog: <String>[
        'previous-attempt-rejected: ${correction ?? "user rejected the generated surface; re-evaluate"}',
      ],
    );
  }

  // ---- internals ----------------------------------------------------------

  Future<void> _runListenLoop() async {
    try {
      while (_conversationActive) {
        final transcript = await _captureUtterance();
        if (!_conversationActive) break;
        if (transcript == null) {
          _conversationActive = false;
          break;
        }
        if (transcript.trim().isEmpty) continue;
        await _respondTo(transcript);
        // While awaiting user confirmation we pause the listen loop —
        // the next iteration starts after [confirmSurface].
        if (state.stage == AssistantStage.awaitingConfirmation) break;
      }
    } on Object catch (e) {
      _conversationActive = false;
      emit(
        state.copyWith(
          stage: AssistantStage.error,
          errorMessage: e.toString(),
        ),
      );
      return;
    }

    if (state.stage != AssistantStage.degraded &&
        state.stage != AssistantStage.error &&
        state.stage != AssistantStage.awaitingConfirmation) {
      emit(state.copyWith(stage: AssistantStage.idle));
    }
  }

  Future<String?> _captureUtterance() async {
    if (!_recorder.isOpen) {
      try {
        await _recorder.open();
      } on MicrophonePermissionException {
        emit(state.copyWith(
          stage: AssistantStage.error,
          errorMessage: 'Microphone permission is required to talk to Aegis.',
        ));
        return null;
      } on Object catch (e) {
        emit(state.copyWith(
          stage: AssistantStage.error,
          errorMessage: e.toString(),
        ));
        return null;
      }
    }

    Stream<Float32List> audioStream;
    try {
      audioStream = await _recorder.startStream();
    } on Object catch (e) {
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: e.toString(),
      ));
      return null;
    }

    emit(state.copyWith(
      stage: AssistantStage.listening,
      transcript: '',
      response: '',
      errorMessage: null,
    ));

    final completer = Completer<String?>();

    _sttSub = _stt
        .transcribeStream(audioStream, language: _languageCode)
        .listen(
      (update) {
        if (!_conversationActive) return;
        switch (update) {
          case SttPartial(:final text):
            emit(state.copyWith(transcript: text));
          case SttFinal(:final text):
            emit(state.copyWith(
              stage: AssistantStage.transcribing,
              transcript: text,
            ));
            if (!completer.isCompleted) completer.complete(text);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete('');
      },
      cancelOnError: true,
    );

    String? captured;
    try {
      captured = await completer.future;
    } on Object catch (e) {
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: e.toString(),
      ));
      captured = null;
    }

    await _sttSub?.cancel();
    _sttSub = null;
    try {
      await _recorder.cancel();
    } on Object {
      // best-effort
    }

    return captured;
  }

  /// Run the LLM on [transcript] through the genui-aware
  /// [LlmService.triageStream] and route the streamed output to TTS +
  /// the inline A2UI surface. The agent decides per-turn whether to
  /// emit a surface (triage flow) or pure text (ask flow); both
  /// outcomes share this same code path.
  Future<void> _respondTo(
    String transcript, {
    List<String> extraIncidentLog = const <String>[],
  }) async {
    emit(state.copyWith(
      stage: AssistantStage.thinking,
      response: '',
      surfaceReady: false,
      thinkingTrace: '',
    ));
    await _llmSub?.cancel();
    await _surfaceUpdatesSub?.cancel();
    _transport?.dispose();
    _autoConfirmTimer?.cancel();

    // Build the incident log from prior turns so the one-shot triage
    // session still sees conversational context (the LiteRT-LM session
    // doesn't survive across turns — see LlmService docs). We cap the
    // replay to the last [_historyTurnsForReplay] turns to keep us
    // inside the engine's prefill budget — the full chat history is
    // still visible in the UI.
    final history = <String>[];
    final replay = state.turns.length > _historyTurnsForReplay
        ? state.turns.sublist(state.turns.length - _historyTurnsForReplay)
        : state.turns;
    for (final turn in replay) {
      history.add('user: ${turn.user}');
      // Summarise long replies — the full text is rendered in the UI;
      // the model only needs a short hint that it answered earlier.
      final summary = turn.assistant.length > 160
          ? '${turn.assistant.substring(0, 160)}…'
          : turn.assistant;
      history.add('aegis: $summary');
    }
    history.addAll(extraIncidentLog);

    final transport = genui.A2uiTransportAdapter();
    _transport = transport;
    transport.incomingMessages.listen(_surfaceController.handleMessage);

    final responseBuffer = StringBuffer();
    final pending = StringBuffer();
    var spokeAtLeastOne = false;
    var sawSurface = false;

    void flushSentences({bool force = false}) {
      final text = pending.toString();
      final cut = force ? text.length : _lastSentenceBoundary(text);
      if (cut <= 0) return;
      final speakable = text.substring(0, cut).trim();
      pending
        ..clear()
        ..write(text.substring(cut));
      if (speakable.isEmpty) return;
      if (!spokeAtLeastOne) {
        spokeAtLeastOne = true;
        emit(state.copyWith(stage: AssistantStage.speaking));
      }
      unawaited(_tts.enqueue(speakable));
    }

    transport.incomingText.listen(
      (chunk) {
        if (!_conversationActive && state.stage != AssistantStage.thinking) {
          return;
        }
        responseBuffer.write(chunk);
        pending.write(chunk);
        emit(state.copyWith(response: responseBuffer.toString()));
        flushSentences();
      },
    );

    _surfaceUpdatesSub = _surfaceController.surfaceUpdates.listen((_) {
      if (state.surfaceReady) return;
      sawSurface = true;
      emit(state.copyWith(surfaceReady: true));
    });

    final completer = Completer<void>();
    _llmSub = _llm
        .triageStream(TriageInput(
          userText: transcript,
          incidentLog: history,
        ))
        .listen(
      transport.addChunk,
      onDone: () async {
        try {
          await transport.flush();
        } on Object {
          // best-effort
        }
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
      flushSentences(force: true);
      if (spokeAtLeastOne) {
        await _tts.whenIdle;
      }

      final assistantText = responseBuffer.toString().trim();
      final committed = ConversationTurn(
        user: transcript.trim(),
        assistant: assistantText,
        hadSurface: sawSurface,
      );
      emit(state.copyWith(
        turns: List.unmodifiable(<ConversationTurn>[
          ...state.turns,
          committed,
        ]),
        transcript: '',
        response: '',
        thinkingTrace: assistantText,
      ));

      // If the agent emitted a surface, pause for verification. The
      // ConfirmActionBar inside the surface (or the auto-timer if the
      // model didn't include one) drives the next transition.
      if (sawSurface) {
        emit(state.copyWith(stage: AssistantStage.awaitingConfirmation));
        if (!_surfaceHasConfirmBar()) {
          // Lightweight reply with a surface but no explicit confirm —
          // treat as Ask-style and auto-advance after a quiet window.
          _autoConfirmTimer = Timer(
            const Duration(seconds: 3),
            confirmSurface,
          );
        }
      }
    } on Object catch (e) {
      if (_conversationActive) {
        emit(state.copyWith(
          stage: AssistantStage.error,
          errorMessage: e.toString(),
        ));
        _conversationActive = false;
      }
    } finally {
      await _llmSub?.cancel();
      _llmSub = null;
    }
  }

  /// Routed from `ConfirmActionBar` taps via `SurfaceController.onSubmit`.
  /// genui packages each tap as a `ChatMessage` whose only part is a
  /// `UiInteractionPart` containing a JSON envelope of the form
  /// `{ "version": "v0.9", "action": { "name": "confirm", ... } }`.
  void _onSurfaceSubmit(genui.ChatMessage message) {
    final actionName = _firstActionName(message);
    if (actionName == null) return;
    switch (actionName) {
      case 'confirm':
        confirmSurface();
      case 'reject':
        rejectSurface();
      default:
        if (kDebugMode) {
          debugPrint('[AssistantCubit] ignoring surface action "$actionName"');
        }
    }
  }

  static String? _firstActionName(genui.ChatMessage message) {
    for (final part in message.parts.uiInteractionParts) {
      try {
        final decoded = jsonDecode(part.interaction);
        if (decoded is Map) {
          final action = decoded['action'];
          if (action is Map) {
            final name = action['name'];
            if (name is String) return name;
          }
        }
      } on FormatException {
        // Drop malformed envelopes; the surface keeps working.
      }
    }
    return null;
  }

  /// Walk the live surface tree looking for any ConfirmActionBar
  /// component. We use this to decide whether the model is asking for
  /// explicit confirmation (Triage-style) or whether we should
  /// auto-advance after a quiet window (Ask-style).
  bool _surfaceHasConfirmBar() {
    try {
      final ctx = _surfaceController.contextFor(surfaceId);
      final def = ctx.definition.value;
      if (def == null) return false;
      for (final component in def.components.values) {
        if (component.type == 'ConfirmActionBar') return true;
      }
      return false;
    } on Object {
      return false;
    }
  }

  List<VoiceModelPack> _orderedTtsPacks(
    List<VoiceModelPack> packs,
    String? langCode,
  ) {
    if (packs.isEmpty) return const <VoiceModelPack>[];
    if (langCode == null || langCode.isEmpty) return List.of(packs);
    final code = langCode.toLowerCase();
    final preferred = <VoiceModelPack>[];
    final rest = <VoiceModelPack>[];
    for (final pack in packs) {
      if (pack.languageCodes.contains(code)) {
        preferred.add(pack);
      } else {
        rest.add(pack);
      }
    }
    return [...preferred, ...rest];
  }

  int _lastSentenceBoundary(String text) {
    if (text.isEmpty) return 0;
    final pattern = RegExp(r'[.!?…।。！？]+["”’\)\]]?\s|\n+');
    var lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      lastEnd = match.end;
    }
    return lastEnd;
  }

  @override
  Future<void> close() async {
    _conversationActive = false;
    _autoConfirmTimer?.cancel();
    await _sttSub?.cancel();
    await _llmSub?.cancel();
    await _surfaceUpdatesSub?.cancel();
    await _actionSub.cancel();
    _transport?.dispose();
    _surfaceController.dispose();
    await _recorder.dispose();
    return super.close();
  }
}
