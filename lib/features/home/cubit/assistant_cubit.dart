import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:genui/genui.dart' as genui;
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/model_catalog.dart';
import '../../../core/voice/model_pack.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/triage_input.dart';
import '../../../core/voice/tts_service.dart';
import '../../reports/data/report.dart';
import '../../reports/data/reports_repository.dart';
import '../widgets/aegis_catalog.dart';

part 'assistant_cubit.freezed.dart';

/// One completed back-and-forth in a conversation. Appended to
/// [AssistantState.turns] when the model finishes responding to a turn so
/// the UI can render the running history (the previous transcript/response
/// pair otherwise gets clobbered the moment the next utterance starts).
/// Snapshot of the user's most recent intake evidence — what the
/// model is reasoning about right now, OR what was attached to the
/// last committed turn. Published via [AssistantCubit.evidenceSink]
/// so catalog widgets can render the original photo + transcript
/// alongside the LLM-emitted report without depending on a
/// BlocProvider inheritance chain that genui's Surface widget
/// breaks.
@immutable
class AssistantEvidenceSnapshot {
  const AssistantEvidenceSnapshot({
    this.image,
    this.audio,
    this.text = '',
  });

  final Uint8List? image;
  final Uint8List? audio;
  final String text;

  bool get isEmpty =>
      (image == null || image!.isEmpty) &&
      (audio == null || audio!.isEmpty) &&
      text.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssistantEvidenceSnapshot &&
          other.text == text &&
          (other.image?.length ?? 0) == (image?.length ?? 0) &&
          (other.audio?.length ?? 0) == (audio?.length ?? 0);

  @override
  int get hashCode => Object.hash(text, image?.length, audio?.length);
}

@immutable
class ConversationTurn {
  const ConversationTurn({
    required this.user,
    required this.assistant,
    this.surfaceMessages = const <genui.A2uiMessage>[],
    this.userImage,
    this.userAudio,
  });

  final String user;
  final String assistant;

  /// WAV bytes (mono 16 kHz IEEE-float32) of the voice intake the user
  /// attached to this turn. Replayed inside the IncidentReportCard's
  /// evidence block so the responder can hear the original recording.
  final Uint8List? userAudio;

  /// Frozen snapshot of the A2UI messages the agent emitted on this
  /// turn — replayed into a private SurfaceController when the user
  /// taps "Action card was shown" to inspect the original UI. Empty
  /// when the turn was a plain text reply.
  final List<genui.A2uiMessage> surfaceMessages;

  /// JPEG bytes of the photo the user attached during intake. Rendered
  /// as a thumbnail above the user's text bubble in the chat history so
  /// the conversation reads back like the actual context the model saw.
  /// Null when the user submitted text-only.
  final Uint8List? userImage;

  bool get hadSurface => surfaceMessages.isNotEmpty;

  /// We deliberately exclude [surfaceMessages] from equality —
  /// genui's [genui.A2uiMessage] is not value-equatable, and the user
  /// + assistant text already disambiguates two distinct turns. Using
  /// the message list in `==` would trigger ListEquals work on every
  /// rebuild for no observable benefit.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationTurn &&
          other.user == user &&
          other.assistant == assistant &&
          other.surfaceMessages.length == surfaceMessages.length &&
          (other.userImage?.length ?? 0) == (userImage?.length ?? 0);

  @override
  int get hashCode =>
      Object.hash(user, assistant, surfaceMessages.length, userImage?.length);

  @override
  String toString() => 'ConversationTurn(user: $user, '
      'assistant: $assistant, messages: ${surfaceMessages.length}, '
      'imageBytes: ${userImage?.length ?? 0})';
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
    // JPEG bytes for the photo attached to the in-flight turn. Non-null
    // only between intake-submit and turn-commit; cleared once the
    // ConversationTurn has captured the bytes. Drives the user-side
    // image thumbnail while the LLM is reasoning so the user can see
    // exactly what context the model is working with.
    Uint8List? pendingUserImage,
    Uint8List? pendingUserAudio,
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
    required ReportsRepository reports,
    required String countryCode,
    String? languageCode,
    Duration autoConfirmTimeout = const Duration(seconds: 30),
  })  : _recorder = recorder,
        _stt = stt,
        _llm = llm,
        _tts = tts,
        _reports = reports,
        _countryCode = countryCode,
        _languageCode = languageCode,
        _autoConfirmTimeout = autoConfirmTimeout,
        _catalog = buildAegisCatalog(),
        super(const AssistantState()) {
    _surfaceController = genui.SurfaceController(catalogs: [_catalog]);
    _actionSub = _surfaceController.onSubmit.listen(_onSurfaceSubmit);
    _llm.setTriageCatalog(_catalog);
    _bootstrap();
  }

  static const String surfaceId = 'aegis-home';

  /// Static evidence broadcast so catalog widgets can render the
  /// user's most recent intake (image bytes + transcript text) without
  /// going through BlocProvider. genui's `Surface` widget mounts its
  /// children via an internal element tree that does NOT inherit our
  /// `BlocProvider<AssistantCubit>` scope — wrapping the Surface in a
  /// `BlocProvider.value` above it is not enough, because the
  /// CatalogItem builders pull their `BuildContext` from inside that
  /// internal tree. A top-level `ValueNotifier` sidesteps the
  /// inheritance problem entirely. The cubit publishes here on every
  /// `_onIntakeSubmit`, every turn commit, and every reset.
  static final ValueNotifier<AssistantEvidenceSnapshot> evidenceSink =
      ValueNotifier<AssistantEvidenceSnapshot>(
    const AssistantEvidenceSnapshot(),
  );

  /// Catalog handed to the host page so it can mount the same set of
  /// CatalogItems on a snapshot SurfaceController for past-turn replay.
  /// We expose this so chat history can re-render an old surface
  /// without rebuilding the catalog from scratch.
  genui.Catalog get catalog => _catalog;

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
  final ReportsRepository _reports;
  final String _countryCode;
  final String? _languageCode;
  final Duration _autoConfirmTimeout;
  final genui.Catalog _catalog;

  /// Pending intake-card state. Survives across surface re-renders so
  /// the user can attach text + photo + audio in any order before
  /// pressing "Analyse with Aegis". The bytes are kept in memory only
  /// for the duration of the intake — discarded once the analysis
  /// turn fires (or the user navigates away).
  String _pendingIntakeText = '';
  bool _pendingHasPhoto = false;
  bool _pendingHasAudio = false;
  Uint8List? _pendingImageJpeg;
  Uint8List? _pendingAudioWav;
  // Raw LLM output for the most recent generating turn — captured in
  // [_respondTo] and consumed by [confirmSurface] when persisting the
  // confirmed surface to [ReportsRepository]. Reset on every new turn.
  String _lastRawLlmOutput = '';
  String _lastUserText = '';
  Uint8List? _lastUserImage;
  Uint8List? _lastUserAudio;
  String _lastAssistantText = '';

  late final genui.SurfaceController _surfaceController;
  late final StreamSubscription<genui.ChatMessage> _actionSub;

  StreamSubscription<SttUpdate>? _sttSub;
  StreamSubscription<String>? _llmSub;
  StreamSubscription<dynamic>? _surfaceUpdatesSub;
  StreamSubscription<genui.GenerationEvent>? _parserSub;
  Timer? _autoConfirmTimer;
  StreamController<String>? _parserInput;
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
    await _parserSub?.cancel();
    _parserSub = null;
    await _parserInput?.close();
    _parserInput = null;
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

  /// Explicit triage entry point — fired by the "Start triage" button
  /// in the home header. Renders an intake card directly into the
  /// surface controller (no LLM round-trip required, the card is
  /// deterministic). The user fills it in and the card's Submit
  /// action triggers [_onIntakeSubmit] which then runs analysis.
  void startTriage() {
    _pendingIntakeText = '';
    _pendingHasPhoto = false;
    _pendingHasAudio = false;
    _lastRawLlmOutput = '';
    _lastUserText = '';
    _lastAssistantText = '';
    _autoConfirmTimer?.cancel();
    _renderIntakeCard();
    emit(state.copyWith(
      stage: AssistantStage.awaitingConfirmation,
      surfaceReady: true,
      transcript: '',
      response: '',
      thinkingTrace: 'Awaiting evidence — attach a photo, voice note, or '
          'text description, then tap Analyse.',
      errorMessage: null,
    ));
  }

  /// Push a fresh intake card onto the surface controller. We reuse
  /// this from [startTriage], from intake-button taps that mutate the
  /// card's state, and from the rejection flow if the user wants to
  /// go back to the intake step.
  void _renderIntakeCard() {
    _surfaceController
      ..handleMessage(genui.A2uiMessage.fromJson(<String, Object?>{
        'version': 'v0.9',
        'createSurface': <String, Object?>{
          'surfaceId': surfaceId,
          'catalogId': _catalog.catalogId,
          'sendDataModel': true,
        },
      }))
      ..handleMessage(genui.A2uiMessage.fromJson(<String, Object?>{
        'version': 'v0.9',
        'updateComponents': <String, Object?>{
          'surfaceId': surfaceId,
          'components': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'root',
              'component': 'TriageIntakeCard',
              'prompt':
                  'Attach a photo, voice note, or describe the scene.',
              'has_photo': _pendingHasPhoto,
              'has_audio': _pendingHasAudio,
              'text_value': _pendingIntakeText,
            },
          ],
        },
      }));
  }

  /// Confirms the currently displayed surface. If the surface came
  /// from a real LLM-generated triage report (not the intake card),
  /// persist it to [ReportsRepository] before clearing.
  Future<void> confirmSurface() async {
    if (state.stage != AssistantStage.awaitingConfirmation) return;
    _autoConfirmTimer?.cancel();

    // Persist the report only when there's actual LLM output. The
    // intake card sits in awaitingConfirmation too but it has no raw
    // LLM trace — confirming it is a no-op (it's the act of starting
    // triage, not the act of saving one).
    if (_lastRawLlmOutput.isNotEmpty) {
      final id = DateTime.now().toIso8601String();
      // Spill the captured image / voice note to the app's documents
      // directory so the report survives app restarts. Hive stores
      // only the path — opening the report detail loads bytes
      // lazily. File names are scoped by report id so a future
      // delete-report flow can rm the directory wholesale.
      final attachments = await _persistAttachments(
        id: id,
        image: _lastUserImage,
        audio: _lastUserAudio,
      );
      final report = Report(
        id: id,
        userText: _lastUserText,
        assistantText: _lastAssistantText,
        createdAt: DateTime.now(),
        rawLlmOutput: _lastRawLlmOutput,
        imagePath: attachments.imagePath,
        audioPath: attachments.audioPath,
      );
      try {
        await _reports.save(report);
        if (kDebugMode) {
          debugPrint(
            '[Aegis][Cubit] saved report id=$id '
            'userChars=${_lastUserText.length} '
            'assistantChars=${_lastAssistantText.length} '
            'rawChars=${_lastRawLlmOutput.length} '
            'image=${attachments.imagePath ?? "-"} '
            'audio=${attachments.audioPath ?? "-"}',
          );
        }
      } on Object catch (e, st) {
        if (kDebugMode) {
          debugPrint('[Aegis][Cubit] save report failed: $e');
          debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] save stack');
        }
      }
    }

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
    Uint8List? intakeImage,
    Uint8List? intakeAudioWav,
  }) async {
    emit(state.copyWith(
      stage: AssistantStage.thinking,
      response: '',
      surfaceReady: false,
      thinkingTrace: '',
    ));
    await _llmSub?.cancel();
    await _surfaceUpdatesSub?.cancel();
    await _parserSub?.cancel();
    _parserSub = null;
    await _parserInput?.close();
    _parserInput = null;
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

    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] _respondTo begin '
        'transcriptLen=${transcript.length} '
        'historyTurns=${replay.length} '
        'historyEntries=${history.length} '
        'extraLog=${extraIncidentLog.length}',
      );
    }

    // We bypass genui's [A2uiTransportAdapter] entirely. Its
    // `incomingText` getter does `.text.trim()` on every TextEvent,
    // which strips the leading/trailing space LiteRT-LM puts on each
    // streamed token — collapsing "Yes, I can hear you." into
    // "Yes,Icanhearyou." (observed). Since we own the LLM stream
    // ourselves, we feed it straight into [A2uiParserTransformer]
    // and consume the parsed events without trim. JSON envelopes
    // become A2uiMessageEvents (routed to the surface controller);
    // everything else stays a TextEvent and goes to TTS + UI as-is.
    final parserInput = StreamController<String>();
    _parserInput = parserInput;
    final capturedMessages = <genui.A2uiMessage>[];
    var textChunkCount = 0;
    var textCharCount = 0;
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

    _parserSub = parserInput.stream
        .transform(const genui.A2uiParserTransformer())
        .listen((event) {
      if (event is genui.A2uiMessageEvent) {
        capturedMessages.add(event.message);
        if (kDebugMode) {
          final summary = _summariseA2uiMessage(event.message);
          debugPrint(
            '[Aegis][Cubit] genui message #${capturedMessages.length} '
            'type=${event.message.runtimeType} $summary',
          );
        }
        _surfaceController.handleMessage(event.message);
        return;
      }
      if (event is genui.TextEvent) {
        if (!_conversationActive && state.stage != AssistantStage.thinking) {
          return;
        }
        // NB: NO trim here — we want to preserve every space so the
        // streamed reply reads as natural language for both the chat
        // bubble and the TTS engine.
        final chunk = event.text;
        if (chunk.isEmpty) return;
        if (kDebugMode) {
          textChunkCount++;
          textCharCount += chunk.length;
        }
        responseBuffer.write(chunk);
        pending.write(chunk);
        emit(state.copyWith(response: responseBuffer.toString()));
        flushSentences();
      }
    });

    _surfaceUpdatesSub = _surfaceController.surfaceUpdates.listen((evt) {
      // Only flip `surfaceReady` once the surface actually has a
      // renderable root. genui's `CreateSurface` envelope keeps the
      // previous component map intact (it only mutates `catalogId` /
      // `theme`), so an early flip would render the *previous* surface
      // — typically the still-mounted intake card — until the model's
      // `UpdateComponents` finally arrives. The user can then re-tap
      // "Analyse with Aegis", cancelling the in-flight stream and
      // forcing a new round-trip.
      final renderable = _hasRenderableSurface();
      if (kDebugMode) {
        debugPrint(
          '[Aegis][Cubit] surfaceUpdate ${evt.runtimeType} '
          'renderable=$renderable',
        );
      }
      if (!renderable) return;
      if (state.surfaceReady) return;
      sawSurface = true;
      emit(state.copyWith(surfaceReady: true));
    });

    // Capture the raw token stream as it flows past — needed to
    // persist the report at confirm-time. We tee into a string
    // buffer and then forward the chunk to the parser. Reset on
    // every turn so the buffer reflects only this generation.
    final rawBuffer = StringBuffer();

    final completer = Completer<void>();
    final streamSw = Stopwatch()..start();
    var firstTokenMs = -1;
    var rawTokenCount = 0;
    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] triageStream subscribe '
        'imageBytes=${intakeImage?.length ?? 0} '
        'historyLines=${history.length}',
      );
    }
    final gpsContext = await _resolveGpsContext();
    _llmSub = _llm
        .triageStream(TriageInput(
          userText: transcript,
          incidentLog: history,
          imageJpeg: intakeImage,
          audioWav: intakeAudioWav,
          gpsContext: gpsContext,
        ))
        .listen(
      (chunk) {
        if (kDebugMode) {
          rawTokenCount++;
          if (firstTokenMs < 0) {
            firstTokenMs = streamSw.elapsedMilliseconds;
            debugPrint(
              '[Aegis][Cubit] triageStream first-token '
              'elapsedMs=$firstTokenMs '
              'firstChunk=${jsonEncode(chunk.length > 80 ? "${chunk.substring(0, 80)}…" : chunk)}',
            );
          }
        }
        rawBuffer.write(chunk);
        parserInput.add(chunk);
      },
      onDone: () async {
        if (kDebugMode) {
          debugPrint(
            '[Aegis][Cubit] triageStream onDone '
            'rawTokens=$rawTokenCount '
            'rawChars=${rawBuffer.length} '
            'elapsedMs=${streamSw.elapsedMilliseconds}',
          );
        }
        try {
          await parserInput.close();
          // Wait for the parser to drain whatever it had buffered.
          await _parserSub?.asFuture<void>();
        } on Object {
          // best-effort — the parser may already be closed
        }
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          final preview = rawBuffer.toString();
          final clipped = preview.length > 400
              ? '${preview.substring(0, 400)}…'
              : preview;
          debugPrint(
            '[Aegis][Cubit] triageStream onError '
            'rawTokens=$rawTokenCount '
            'rawChars=${rawBuffer.length} '
            'elapsedMs=${streamSw.elapsedMilliseconds} '
            'error=$e',
          );
          debugPrint('[Aegis][Cubit] triageStream rawSoFar:\n$clipped');
          debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] triageStream stack');
        }
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
      flushSentences(force: true);

      // Empty surface guard: a `createSurface` envelope by itself is
      // worthless — there's no root component to render. The model
      // sometimes stops short after the first envelope (token budget
      // or just confusion). Treat that as a plain-reply turn so the
      // user doesn't see an empty card.
      final usableSurface = sawSurface && _hasRenderableSurface();
      if (kDebugMode) {
        final componentTypes = _surfaceComponentTypes();
        debugPrint(
          '[Aegis][Cubit] _respondTo stream done '
          'sawSurface=$sawSurface '
          'usableSurface=$usableSurface '
          'a2uiMessages=${capturedMessages.length} '
          'surfaceComponents=${componentTypes.length} '
          '[${componentTypes.join(",")}] '
          'textChunks=$textChunkCount textChars=$textCharCount '
          'spokeAtLeastOne=$spokeAtLeastOne',
        );
        final preview = rawBuffer.toString();
        final clipped = preview.length > 800
            ? '${preview.substring(0, 800)}…'
            : preview;
        debugPrint('[Aegis][Cubit] rawOutput:\n$clipped');
      }
      if (spokeAtLeastOne) {
        await _tts.whenIdle;
      }

      final assistantText = responseBuffer.toString().trim();
      // Stash raw output + texts for [confirmSurface] to persist.
      // Cleared on the next [_respondTo] turn so we don't accidentally
      // re-save the previous one.
      _lastRawLlmOutput = usableSurface ? rawBuffer.toString() : '';
      // Drop the "(see attached evidence)" placeholder we feed the
      // LLM when the user submits only attachments — it's
      // model-prompt scaffolding, not something the user typed, so
      // it shouldn't end up in the chat bubble or persisted report.
      const placeholder = '(see attached evidence)';
      final committedUserText =
          transcript.trim() == placeholder ? '' : transcript.trim();
      _lastUserText = committedUserText;
      _lastAssistantText = assistantText;
      _lastUserImage = intakeImage ?? state.pendingUserImage;
      _lastUserAudio = intakeAudioWav;
      final committed = ConversationTurn(
        user: committedUserText,
        assistant: assistantText,
        userImage: intakeImage ?? state.pendingUserImage,
        userAudio: intakeAudioWav,
        surfaceMessages: usableSurface
            ? List.unmodifiable(capturedMessages)
            : const <genui.A2uiMessage>[],
      );
      emit(state.copyWith(
        turns: List.unmodifiable(<ConversationTurn>[
          ...state.turns,
          committed,
        ]),
        transcript: '',
        response: '',
        thinkingTrace: assistantText,
        pendingUserImage: null,
        pendingUserAudio: null,
      ));
      AssistantCubit.evidenceSink.value = AssistantEvidenceSnapshot(
        image: committed.userImage,
        audio: committed.userAudio,
        text: committed.user,
      );

      // If the agent emitted a usable surface, pause for verification.
      // ConfirmActionBar inside the surface OR the auto-timer drives
      // the next transition.
      if (usableSurface) {
        final hasConfirmBar = _surfaceHasConfirmBar();
        if (kDebugMode) {
          debugPrint(
            '[Aegis][Cubit] surface verification '
            'hasConfirmBar=$hasConfirmBar '
            'autoConfirmIn=${hasConfirmBar ? "manual" : "${_autoConfirmTimeout.inSeconds}s"}',
          );
        }
        emit(state.copyWith(stage: AssistantStage.awaitingConfirmation));
        if (!hasConfirmBar) {
          _autoConfirmTimer = Timer(
            _autoConfirmTimeout,
            confirmSurface,
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            sawSurface
                ? '[Aegis][Cubit] surface dropped — createSurface only, no components'
                : '[Aegis][Cubit] turn committed (no surface, plain reply)',
          );
        }
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        final preview = rawBuffer.toString();
        final clipped = preview.length > 800
            ? '${preview.substring(0, 800)}…'
            : preview;
        debugPrint(
          '[Aegis][Cubit] _respondTo failed '
          'rawTokens=$rawTokenCount '
          'rawChars=${rawBuffer.length} '
          'capturedMessages=${capturedMessages.length} '
          'sawSurface=$sawSurface '
          'error=$e',
        );
        if (preview.isNotEmpty) {
          debugPrint('[Aegis][Cubit] _respondTo rawSoFar:\n$clipped');
        }
        debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] _respondTo stack');
      }
      if (_conversationActive) {
        emit(state.copyWith(
          stage: AssistantStage.error,
          errorMessage: e.toString(),
          pendingUserImage: null,
          pendingUserAudio: null,
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
    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] surface action received name=${actionName ?? "null"}',
      );
    }
    if (actionName == null) return;
    switch (actionName) {
      case 'confirm':
        confirmSurface();
      case 'reject':
        rejectSurface();
      case 'intake_text':
        _intakeTextRequested.add(null);
      case 'intake_photo':
        // The view owns the system picker (it needs a BuildContext).
        // We just ask — bytes flow back via [setIntakePhoto].
        _intakePhotoRequested.add(null);
      case 'intake_audio':
        unawaited(_captureIntakeAudio());
      case 'intake_submit':
        unawaited(_onIntakeSubmit());
      default:
        if (kDebugMode) {
          debugPrint(
            '[Aegis][Cubit] ignoring unknown surface action "$actionName"',
          );
        }
    }
  }

  /// Fires when the user taps the "Text" pill on the intake card. The
  /// view subscribes via [intakeTextRequests] and opens a text-entry
  /// modal; the result flows back through [setIntakeText].
  Stream<void> get intakeTextRequests => _intakeTextRequested.stream;
  final StreamController<void> _intakeTextRequested =
      StreamController<void>.broadcast();

  /// Fires when the user taps the "Photo" pill on the intake card. The
  /// view owns the system picker (needs a [BuildContext]) — it opens
  /// `image_picker`, shrinks the result, and pushes the JPEG bytes
  /// back via [setIntakePhoto].
  Stream<void> get intakePhotoRequests => _intakePhotoRequested.stream;
  final StreamController<void> _intakePhotoRequested =
      StreamController<void>.broadcast();

  /// Fires when an intake action surfaces user-facing feedback (eg.
  /// recording started / failed). The view shows the broadcast
  /// message in a snackbar.
  Stream<String> get intakeStubRequests => _intakeStubRequested.stream;
  final StreamController<String> _intakeStubRequested =
      StreamController<String>.broadcast();

  /// Update the pending intake text and re-render the card so the
  /// pill flips to its "attached" state.
  void setIntakeText(String text) {
    _pendingIntakeText = text.trim();
    if (state.surfaceReady) {
      _renderIntakeCard();
    }
  }

  /// Accept a JPEG (or any image bytes the platform handed us),
  /// downscale to 512px on the longest edge, and store. Re-renders the
  /// intake card so the Photo pill flips to attached.
  ///
  /// We resize off the UI thread via [compute] when the input is
  /// large — the `image` package is pure Dart but [img.copyResize] on
  /// a 12MP frame can take 200-400ms, which is enough to drop frames.
  Future<void> setIntakePhoto(Uint8List rawBytes) async {
    if (rawBytes.isEmpty) return;
    Uint8List shrunk;
    try {
      shrunk = await compute(_shrinkJpeg, rawBytes);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] image shrink failed: $e');
      }
      _intakeStubRequested.add(
        'Could not process that photo. Try another one.',
      );
      return;
    }
    _pendingImageJpeg = shrunk;
    _pendingHasPhoto = true;
    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] intake photo attached '
        'rawBytes=${rawBytes.length} shrunkBytes=${shrunk.length}',
      );
    }
    if (state.surfaceReady) {
      _renderIntakeCard();
    }
  }

  /// Voice intake — reuses the existing mic+VAD+STT pipeline so the
  /// user gets the same listening UX as the conversation loop. The
  /// transcript is appended to the intake text and the Voice pill
  /// flips to attached. We don't keep raw WAV around: the 1024-token
  /// model bundle can't reliably grade audio independently of text,
  /// so transcription is the load-bearing signal.
  Future<void> _captureIntakeAudio() async {
    if (!_voiceReady) {
      _intakeStubRequested.add('Voice models are not ready yet.');
      return;
    }
    if (!_recorder.isOpen) {
      try {
        await _recorder.open();
      } on MicrophonePermissionException {
        _intakeStubRequested.add(
          'Microphone permission is required for voice intake.',
        );
        return;
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint('[Aegis][Cubit] intake recorder open failed: $e');
        }
        _intakeStubRequested.add('Could not open microphone.');
        return;
      }
    }

    Stream<Float32List> audioStream;
    try {
      audioStream = await _recorder.startStream();
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] intake recorder start failed: $e');
      }
      _intakeStubRequested.add('Could not start recording.');
      return;
    }

    emit(state.copyWith(stage: AssistantStage.listening));

    Uint8List? wav;
    try {
      // 30s safety cap so a stuck VAD never hangs the intake. The
      // real endpoint is the trailing-silence timer inside
      // [SttService.recordToWav] (~1.2 s after the last detected
      // speech sample), so this only fires when the mic streams
      // pure noise / the user forgets to stop.
      wav = await _stt
          .recordToWav(audioStream)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] intake voice capture timed out');
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] intake voice capture failed: $e');
        debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] intake stack');
      }
    } finally {
      try {
        await _recorder.cancel();
      } on Object {
        // best-effort
      }
    }

    if (wav == null || wav.isEmpty) {
      _intakeStubRequested.add('Did not catch any speech. Try again.');
      emit(state.copyWith(stage: AssistantStage.awaitingConfirmation));
      _renderIntakeCard();
      return;
    }

    _pendingAudioWav = wav;
    _pendingHasAudio = true;
    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] intake voice attached wavBytes=${wav.length}',
      );
    }
    emit(state.copyWith(stage: AssistantStage.awaitingConfirmation));
    _renderIntakeCard();
  }

  Future<void> _onIntakeSubmit() async {
    final text = _pendingIntakeText.trim();
    final hasImage = _pendingImageJpeg != null;
    final hasAudio = _pendingAudioWav != null && _pendingAudioWav!.isNotEmpty;
    // Need at least one signal — empty text, no image, no audio isn't
    // analysable.
    if (text.isEmpty && !hasImage && !hasAudio) {
      _intakeStubRequested.add(
        'Add a description, photo, or voice note before analysing.',
      );
      return;
    }
    // Drop surfaceReady so the view flips from intake card → "Aegis is
    // reasoning…" spinner. The LLM's createSurface envelope will
    // overwrite the surface registry entry by id, and surfaceReady
    // flips back to true once it lands. Also stash the user's input
    // (text + image bytes) on the state so the chat shows the user
    // bubble immediately — without it the screen sits blank for the
    // 15-30s the engine spends on prefill + first token. When the
    // user submitted only attachments, leave the transcript bubble
    // empty — the image / audio chips carry the message; a "(see
    // attached evidence)" placeholder reads like noise. The LLM
    // still gets that hint via the user prompt builder.
    final llmUserText =
        text.isEmpty ? '(see attached evidence)' : text;
    emit(state.copyWith(
      surfaceReady: false,
      transcript: text,
      pendingUserImage: _pendingImageJpeg,
      pendingUserAudio: _pendingAudioWav,
    ));
    AssistantCubit.evidenceSink.value = AssistantEvidenceSnapshot(
      image: _pendingImageJpeg,
      audio: _pendingAudioWav,
      text: text,
    );
    // Wipe the existing surface so the still-mounted TriageIntakeCard
    // disappears the moment the user taps "Analyse with Aegis". Without
    // this the card hangs around between the cubit's `surfaceReady=false`
    // emit and the model's first `UpdateComponents` envelope (15-90s
    // later), and a panicky re-tap of the still-active button cancels
    // the in-flight stream and forces another round-trip. genui's
    // `CreateSurface` envelope only mutates `catalogId`/`theme`, so we
    // need an explicit `DeleteSurface` to clear the component map.
    _surfaceController.handleMessage(
      genui.A2uiMessage.fromJson(<String, Object?>{
        'version': 'v0.9',
        'deleteSurface': <String, Object?>{'surfaceId': surfaceId},
      }),
    );
    _conversationActive = true;
    await _respondTo(
      llmUserText,
      intakeImage: _pendingImageJpeg,
      intakeAudioWav: _pendingAudioWav,
    );
    _conversationActive = false;
    // Drop the captured bytes — they're already in the LLM context.
    _pendingImageJpeg = null;
    _pendingAudioWav = null;
    _pendingHasPhoto = false;
    _pendingHasAudio = false;
    _pendingIntakeText = '';
  }

  /// Pure-Dart JPEG re-encoder used by [compute]. Decodes any image
  /// format `image` understands, scales the longest edge to 512px,
  /// re-encodes as JPEG quality 80. Top-level so isolate spawn can
  /// reach it.
  static Uint8List _shrinkJpeg(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw const FormatException('Unsupported image format');
    }
    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final scaled = longest > 512
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 512 : null,
            height: decoded.height > decoded.width ? 512 : null,
          )
        : decoded;
    final bytes = img.encodeJpg(scaled, quality: 80);
    return Uint8List.fromList(bytes);
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

  static String _summariseA2uiMessage(genui.A2uiMessage msg) {
    if (msg is genui.CreateSurface) {
      return 'surfaceId=${msg.surfaceId} catalog=${msg.catalogId}';
    }
    if (msg is genui.UpdateComponents) {
      final ids = msg.components
          .map((c) => '${c.id}:${c.type}')
          .take(8)
          .join(',');
      final more =
          msg.components.length > 8 ? '+${msg.components.length - 8}' : '';
      return 'surfaceId=${msg.surfaceId} count=${msg.components.length} '
          '[$ids$more]';
    }
    if (msg is genui.UpdateDataModel) {
      return 'surfaceId=${msg.surfaceId} path=${msg.path}';
    }
    if (msg is genui.DeleteSurface) {
      return 'surfaceId=${msg.surfaceId}';
    }
    return '';
  }

  /// Best-effort GPS fix for the in-flight triage turn. Times out fast
  /// (3s) — we don't want a slow lock to delay every report. Returns
  /// null if permission is denied, the service is off, or the lookup
  /// fails; the LLM treats the field as optional and still emits a
  /// report (just with `[UNKNOWN]` for location). Never asks for
  /// permission here — onboarding's permissions step owns that flow.
  /// Writes intake image + audio bytes to the app's documents
  /// directory, keyed by [id], so the persisted [Report] can
  /// reference them by path. Returns a record with the absolute
  /// paths (or null per field when nothing was attached). Best-effort:
  /// a write failure simply produces a null path so the report still
  /// saves with whatever attachments survived.
  Future<({String? imagePath, String? audioPath})> _persistAttachments({
    required String id,
    Uint8List? image,
    Uint8List? audio,
  }) async {
    if ((image == null || image.isEmpty) &&
        (audio == null || audio.isEmpty)) {
      return (imagePath: null, audioPath: null);
    }
    String? imagePath;
    String? audioPath;
    try {
      final docs = await getApplicationDocumentsDirectory();
      // Sanitise the report id (which may be an ISO timestamp with
      // colons) so it's a safe directory name on every filesystem.
      final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final dir = Directory('${docs.path}/aegis-reports/$safeId');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (image != null && image.isNotEmpty) {
        final f = File('${dir.path}/photo.jpg');
        await f.writeAsBytes(image, flush: true);
        imagePath = f.path;
      }
      if (audio != null && audio.isNotEmpty) {
        final f = File('${dir.path}/voice.wav');
        await f.writeAsBytes(audio, flush: true);
        audioPath = f.path;
      }
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] _persistAttachments failed: $e');
      }
    }
    return (imagePath: imagePath, audioPath: audioPath);
  }

  Future<String?> _resolveGpsContext() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      final lat = pos.latitude.toStringAsFixed(5);
      final lng = pos.longitude.toStringAsFixed(5);
      final acc = pos.accuracy.isFinite
          ? ' (±${pos.accuracy.toStringAsFixed(0)}m)'
          : '';
      final ctx = 'lat=$lat, lng=$lng$acc';
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] gpsContext=$ctx');
      }
      return ctx;
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] gps lookup failed: $e');
      }
      return null;
    }
  }

  List<String> _surfaceComponentTypes() {
    try {
      final ctx = _surfaceController.contextFor(surfaceId);
      final def = ctx.definition.value;
      if (def == null) return const <String>[];
      return def.components.values.map((c) => '${c.id}:${c.type}').toList();
    } on Object {
      return const <String>[];
    }
  }

  /// True when the live surface has at least a root component — ie.
  /// the agent emitted both `createSurface` AND `updateComponents`
  /// (rather than just the empty envelope). genui's `Surface` widget
  /// silently renders nothing when the root is missing, so we use
  /// this to decide whether to surface a verification UI at all.
  bool _hasRenderableSurface() {
    try {
      final ctx = _surfaceController.contextFor(surfaceId);
      final def = ctx.definition.value;
      if (def == null) return false;
      return def.components.isNotEmpty &&
          def.components.containsKey('root');
    } on Object {
      return false;
    }
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
    await _parserSub?.cancel();
    await _parserInput?.close();
    await _actionSub.cancel();
    await _intakeTextRequested.close();
    await _intakePhotoRequested.close();
    await _intakeStubRequested.close();
    _surfaceController.dispose();
    await _recorder.dispose();
    return super.close();
  }
}
