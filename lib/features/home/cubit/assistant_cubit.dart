import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/alert/alert_briefing_sink.dart';
import '../../../core/places/place.dart';
import '../../../core/places/places_repository.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/listening_cue_player.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/model_catalog.dart';
import '../../../core/voice/model_pack.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/triage_input.dart';
import '../../../core/voice/triage_report.dart';
import '../../../core/voice/tts_service.dart';
import '../../reports/data/report.dart';
import '../../reports/data/reports_repository.dart';
import 'package:latlong2/latlong.dart';

part 'assistant_cubit.freezed.dart';

/// One completed back-and-forth in a conversation.
@immutable
class ConversationTurn {
  const ConversationTurn({
    required this.user,
    required this.assistant,
    this.report,
    this.userImage,
    this.userAudio,
    this.mapQuery,
    this.mapPlaces,
    this.mapCenter,
  });

  final String user;
  final String assistant;

  /// Set when Gemma 4 emitted a `render_map_view` tool call during this
  /// chat turn. The cubit attaches the parsed query so the inline map
  /// card can render `mapPlaces` against the user's centre point.
  final MapViewQuery? mapQuery;

  /// Result of running [PlacesRepository.findNearby] against the
  /// model's requested categories + radius. Empty when the offline DB
  /// returned zero hits.
  final List<Place>? mapPlaces;

  /// Resolved centre point used for the [PlacesRepository] query —
  /// live GPS fix or onboarding region. Stored alongside the result so
  /// the inline map can render the user pulse marker at the exact spot
  /// the query ran against.
  final LatLng? mapCenter;

  bool get hasMap =>
      mapQuery != null &&
      mapCenter != null &&
      (mapPlaces?.isNotEmpty ?? false);

  /// Structured triage analysis emitted by Gemma 4 via the
  /// `render_triage_report` native tool call. Non-null only on turns
  /// that ran the triage flow; ask-mode turns leave this null.
  final TriageReport? report;

  /// WAV bytes (mono 16 kHz IEEE-float32) of the voice intake the user
  /// attached to this turn. Replayed inside the report card's evidence
  /// block so the responder can hear the original recording.
  final Uint8List? userAudio;

  /// JPEG bytes of the photo the user attached during intake.
  final Uint8List? userImage;

  bool get hasReport => report != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationTurn &&
          other.user == user &&
          other.assistant == assistant &&
          other.report == report &&
          (other.userImage?.length ?? 0) == (userImage?.length ?? 0);

  @override
  int get hashCode =>
      Object.hash(user, assistant, report, userImage?.length);

  @override
  String toString() => 'ConversationTurn(user: $user, '
      'assistant: $assistant, hasReport: $hasReport, '
      'imageBytes: ${userImage?.length ?? 0})';
  /// Convenience for building a synthetic system/assistant-only turn.
  /// `user` stays empty so the UI knows there is no user-side bubble
  /// to render — the message arrived from a non-conversational source
  /// (e.g. alert briefing pushed by [AlertBriefingSink]).
  ConversationTurn copyWithAssistant(String text) =>
      ConversationTurn(user: user, assistant: text);
}

/// Stage of the assistant pipeline.
enum AssistantStage {
  idle,
  preparing,
  listening,
  transcribing,
  thinking,
  speaking,
  awaitingConfirmation,
  degraded,
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
    Uint8List? pendingUserImage,
    Uint8List? pendingUserAudio,
    @Default(false) bool intakeOpen,
    @Default('') String intakeText,
    @Default(false) bool intakeHasPhoto,
    @Default(false) bool intakeHasAudio,
    @Default(false) bool thinkingForReport,
    Uint8List? intakeImagePreview,
    String? languageCode,
    /// True while the LLM engine is paying its first-run cold-start
    /// cost (shader compile + KV-cache prefill, 10-30 s on Mali/Adreno
    /// GPUs). Drives the home page's "Preparing AI engine…" overlay.
    @Default(false) bool engineWarming,
  }) = _AssistantState;

  const AssistantState._();

  bool get isBusy =>
      stage == AssistantStage.preparing ||
      stage == AssistantStage.listening ||
      stage == AssistantStage.transcribing ||
      stage == AssistantStage.thinking ||
      stage == AssistantStage.speaking ||
      stage == AssistantStage.awaitingConfirmation;

  bool get isConversationActive =>
      stage == AssistantStage.listening ||
      stage == AssistantStage.transcribing ||
      stage == AssistantStage.thinking ||
      stage == AssistantStage.speaking ||
      stage == AssistantStage.awaitingConfirmation;

  bool get canSubmitIntake =>
      intakeText.trim().isNotEmpty || intakeHasPhoto || intakeHasAudio;
}

/// Orchestrates the offline assistant pipeline:
///   mic → STT → LLM (`render_triage_report` tool call) → TTS + fixed
///   report card.
///
/// Replaces the old A2UI surface controller. The model emits one
/// structured `FunctionCallResponse` per triage turn; the cubit parses
/// it into a [TriageReport] and stores it on the [ConversationTurn]
/// the view binds to a [TriageReportCard].
class AssistantCubit extends Cubit<AssistantState> {
  AssistantCubit({
    required AudioRecorderService recorder,
    required SttService stt,
    required LlmService llm,
    required TtsService tts,
    required ReportsRepository reports,
    required String countryCode,
    StorageService? storage,
    AlertBriefingSink? briefingSink,
    PlacesRepository? places,
    String? languageCode,
    Duration autoConfirmTimeout = const Duration(seconds: 30),
  })  : _recorder = recorder,
        _stt = stt,
        _llm = llm,
        _tts = tts,
        _reports = reports,
        _countryCode = countryCode,
        _storage = storage,
        _briefingSink = briefingSink,
        _places = places,
        _languageCode = languageCode,
        _autoConfirmTimeout = autoConfirmTimeout,
        super(AssistantState(languageCode: languageCode)) {
    if (kDebugMode) {
      debugPrint(
        '[AssistantCubit] init country=$countryCode '
            'language=${languageCode ?? "(none — onboarding skipped)"}',
      );
    }
    _attachLifecycleListener();
    _subscribeBriefings();
    _bootstrap();
  }

  /// Cap on prior turns we replay into the per-turn `incidentLog`.
  static const int _historyTurnsForReplay = 4;

  /// Track foreground/background state so we can gate TTS playback on
  /// the alert briefing — speaking while the native [FullScreenAlertActivity]
  /// is on top would compete with the siren and play in the background
  /// even after the takeover screen is dismissed. We only fire TTS when
  /// the app is in [AppLifecycleState.resumed]; briefings that arrive
  /// while paused/inactive (cold-launch path, or while the takeover
  /// activity is covering MainActivity) are stashed in
  /// [_deferredBriefingBody] and spoken on the next resume.
  void _attachLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        _lifecycleState = state;
      },
      onResume: () {
        _lifecycleState = AppLifecycleState.resumed;
        final pending = _deferredBriefingBody;
        if (pending == null) return;
        _deferredBriefingBody = null;
        unawaited(_speakBriefing(pending));
      },
    );
  }

  /// True only when the engine reports [AppLifecycleState.resumed]. The
  /// `paused` / `inactive` / `hidden` / `detached` states all mean the
  /// user is staring at something else (likely the takeover screen) and
  /// audio playback would be either inappropriate or routed to the
  /// background while the siren plays.
  bool get _isAppForeground => _lifecycleState == AppLifecycleState.resumed;

  final AudioRecorderService _recorder;
  final SttService _stt;
  final LlmService _llm;
  final TtsService _tts;
  final ReportsRepository _reports;
  // Asset-backed mic-open / mic-close cues. Replaces the prior
  // `SystemSound.click` calls — see `assets/sound/`.
  final ListeningCuePlayer _cues = ListeningCuePlayer();
  final String _countryCode;
  final Duration _autoConfirmTimeout;

  Uint8List? _pendingImageJpeg;
  Uint8List? _pendingAudioWav;
  TriageReport? _lastReport;
  String _lastUserText = '';
  Uint8List? _lastUserImage;
  Uint8List? _lastUserAudio;
  String _lastAssistantText = '';
  final StorageService? _storage;
  final AlertBriefingSink? _briefingSink;
  final PlacesRepository? _places;
  String? _languageCode;
  MapViewQuery? _pendingMapQuery;
  List<Place>? _pendingMapPlaces;
  LatLng? _pendingMapCenter;

  /// Currently-selected ISO-639 language code (mutable — see
  /// [changeLanguage]). Used by the home header to render the active
  /// option in the language dropdown.
  String? get currentLanguageCode => _languageCode;

  StreamSubscription<SttUpdate>? _sttSub;
  StreamSubscription<ChatStreamEvent>? _llmSub;
  Timer? _autoConfirmTimer;
  StreamSubscription<AlertBriefing>? _briefingSub;
  AppLifecycleListener? _lifecycleListener;
  // Default to `inactive` so the very first briefing handled before
  // [AppLifecycleListener] fires `onResume` is deferred — important
  // on the cold-launch path where the cubit is constructed during
  // MainActivity onCreate, *before* the Flutter engine reports the
  // first lifecycle event. Without this default the in-progress
  // takeover activity would trigger TTS through the cubit.
  AppLifecycleState _lifecycleState = AppLifecycleState.inactive;
  bool _voiceReady = false;
  bool _conversationActive = false;
  String? _lastBriefingAlertId;
  String? _deferredBriefingBody;
  String? _activeBriefingBody;

  /// Subscribe to alert briefings so the in-app surface shows the same
  /// summary text the takeover screen / TTS already deliver. Each
  /// briefing arrives as a synthetic [ConversationTurn] in the chat
  /// history — user-side bubble identifies the alert, assistant-side
  /// bubble carries the model's translated briefing. Subscription is
  /// idempotent on `alertId` so a duplicate broadcast doesn't double
  /// the bubble. Runs even when the assistant is in [AssistantStage.degraded]
  /// (no STT/LLM packs installed) — the briefing is the only
  /// thing degraded users get to see.
  void _subscribeBriefings() {
    final sink = _briefingSink;
    if (sink == null) return;
    _briefingSub = sink.stream.listen(_onBriefing);
    // Cold-launch path: the alert pipeline ran while the app was
    // closed, the briefing was cached on the sink, the takeover
    // screen auto-launched MainActivity, and now we're being mounted
    // for the first time. Replay the cached briefing once so the
    // home screen surfaces it (and the user finally hears it via
    // TTS). [consumePending] makes this idempotent — the next cubit
    // mount during the same session won't re-speak the same alert.
    final pending = sink.pending;
    if (pending != null) {
      sink.consumePending();
      _onBriefing(pending);
    }
  }

  void _onBriefing(AlertBriefing briefing) {
    if (_lastBriefingAlertId == briefing.alertId) return;
    _lastBriefingAlertId = briefing.alertId;
    final body = briefing.briefing.trim();
    if (body.isEmpty) return;
    // Tear down any in-flight conversation BEFORE we show the briefing.
    // Otherwise a background-fired alert that resumes MainActivity finds
    // the mic still hot (from before the user backgrounded), and any
    // siren / TTS / ambient noise leaks into the STT stream as a bogus
    // utterance. fire-and-forget — the briefing emit + TTS path below
    // doesn't depend on the cancel completing.
    if (_conversationActive ||
        state.stage == AssistantStage.listening ||
        state.stage == AssistantStage.transcribing ||
        state.stage == AssistantStage.thinking ||
        state.stage == AssistantStage.speaking) {
      unawaited(stopConversation());
    }
    // Stash so the next mic-driven conversation seeds the chat brain
    // with the briefing as context — the user can ask follow-ups
    // ("what should I do?", "where is the nearest shelter?") without
    // re-explaining the disaster. Cleared in [stopConversation].
    _activeBriefingBody = body;
    _llm.setBriefingContext(body);
    // Empty `user` field — UI treats this as an assistant-only / system
    // message and skips the right-aligned user bubble. The user did
    // not type anything; the message arrived from the alert pipeline.
    final synthetic = const ConversationTurn(
      user: '',
      assistant: '',
    ).copyWithAssistant(body);
    emit(
      state.copyWith(
        turns: List<ConversationTurn>.unmodifiable([...state.turns, synthetic]),
        // Clear in-flight transcript/response so the briefing only
        // renders as a single entry in the [turns] history. Setting
        // `response` here too would double the bubble — the chat list
        // builder appends a separate "in-flight" bubble whenever
        // `response` is non-empty.
        transcript: '',
        response: '',
      ),
    );

    // Gate TTS on foreground state. The native takeover activity
    // (FullScreenAlertActivity) sits on top of MainActivity for ~4 s
    // with the siren going; firing TTS now would compete with the
    // siren AND continue playing in the background after the takeover
    // dismisses. Defer to the next [AppLifecycleListener.onResume]
    // which fires once MainActivity comes back to the foreground after
    // the auto-launch.
    if (_isAppForeground) {
      unawaited(_speakBriefing(body));
    } else {
      _deferredBriefingBody = body;
    }
  }

  /// Switch the active reply / TTS / STT language. Persists the new
  /// code to storage, re-pins Gemma's reply language, and re-runs the
  /// pack-selection bootstrap so STT and TTS pick the right voice
  /// packs for the new locale.
  ///
  /// Stops any in-flight conversation first — pivoting language
  /// mid-utterance would mean the user starts speaking in language A
  /// and the model replies in B with the wrong TTS voice.
  Future<void> changeLanguage(String code) async {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return;
    if (_languageCode == normalized) return;
    if (kDebugMode) {
      debugPrint(
        '[AssistantCubit] changeLanguage from=${_languageCode ?? "(none)"} '
        'to=$normalized',
      );
    }
    if (_conversationActive) {
      await stopConversation();
    }
    _languageCode = normalized;
    emit(state.copyWith(languageCode: normalized));
    await _storage?.setSelectedLanguageCode(normalized);
    _llm.setPreferredLanguage(normalized);
    // Rebuild voice packs (TTS + STT) for the new language. Bootstrap
    // already handles availability + degraded fallbacks; calling it
    // again is the simplest path to a consistent post-switch state.
    await _bootstrap();
  }

  Future<void> _speakBriefing(String body) async {
    try {
      // 0.85× speed — emergency briefings need to land clearly. The
      // chat-reply path uses default 1.0×; this is intentionally
      // slower so a panicked user can parse "evacuate to higher
      // ground" without backtracking.
      if (kDebugMode) {
        debugPrint(
          '[AssistantCubit] briefing TTS speak '
          'lang=${_languageCode ?? "auto"} speed=0.85 chars=${body.length}',
        );
      }
      await _tts.enqueue(body, speed: 0.85);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AssistantCubit] briefing TTS failed: $e\n$st');
      }
    }
  }

  Future<void> _bootstrap() async {
    emit(state.copyWith(stage: AssistantStage.preparing));
    try {
      final plan = ModelCatalog.planFor(_countryCode);
      final ttsPacks = _orderedTtsPacks(plan.tts, _languageCode);
      final vad = plan.vad.isNotEmpty ? plan.vad.first : null;
      final llm = plan.llm.isNotEmpty ? plan.llm.first : null;

      // Block on TTS load. Earlier code used `.ignore()` which raced
      // against the first user turn: if the user spoke before sherpa
      // finished loading, [TtsService.enqueue] threw and the cubit
      // silently swallowed the error (unawaited) — that was the
      // "sometimes TTS plays, sometimes not" symptom. Bootstrap is
      // already gated behind the "preparing" stage so the extra wait
      // is invisible.
      if (ttsPacks.isNotEmpty) {
        try {
          await _tts.loadAll(ttsPacks);
        } on Object catch (e) {
          if (kDebugMode) {
            debugPrint('[Aegis][Cubit] TTS load failed (non-fatal): $e');
          }
        }
      }
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
      // Boot-time engine warm-up disabled. `LlmService.warmUp` runs a
      // text-only decode at maxTokens=1024 to pre-pay the GPU shader
      // compile + KV-cache prefill cost — but it settles the cached
      // engine handle into a text-only GPU state. The first triage
      // turn with an image then reuses that handle, hits the vision
      // encoder on a text-warmed OpenCL context, and crashes mid-
      // decode on Mali (`Conversation closed` straight after
      // `RunDecodeAsync`, followed by `clEnqueueWriteBuffer` /
      // `DYNAMIC_UPDATE_SLICE` on retry's engine_create). The
      // `model_download_speedup` branch — same prompt, same image,
      // same flutter_gemma — ships vision successfully on this
      // hardware precisely because it has no warmUp. First triage /
      // alert pays the ~10s cold-start tax here instead.
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

  // `_warmEngine` (boot-time `LlmService.warmUp` wrapper) intentionally
  // removed — see note at boot setup above. Triage with image on a
  // text-warmed engine crashes mid-decode on Mali. Do not re-add
  // without first moving triage to its own engine instance.

  Future<void> toggleConversation() async {
    // Intake voice capture is its own flow (no full conversation
    // session). If the user taps the mic while it's running, treat
    // the tap as "stop now and submit what we've captured" instead of
    // toggling the chat session.
    if (_intakeAudioActive) {
      _intakeAudioCancel?.complete();
      return;
    }
    if (_conversationActive) {
      await stopConversation();
    } else {
      await startConversation();
    }
  }

  /// Set to true while [_captureIntakeAudio] is sitting on the
  /// recorder. Used by [toggleConversation] so the mic button can
  /// double as an early-stop trigger for triage audio evidence.
  bool _intakeAudioActive = false;
  Completer<void>? _intakeAudioCancel;

  Future<void> startConversation() async {
    if (!_voiceReady) return;
    if (_conversationActive) return;
    _conversationActive = true;
    // Cue the user that mic capture is starting. Two channels because
    // either alone is easy to miss under stress:
    //   * HapticFeedback.mediumImpact — tactile thump, works even when
    //     the device is on silent (which an emergency user may have).
    //   * `ListeningCuePlayer.playStart` — branded mic-on chime
    //     (`assets/sound/listening_start.mp3`); respects ringer volume.
    // Both are best-effort: failures (e.g. emulator without vibrator)
    // silently fall through so the conversation loop still runs.
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_cues.playStart());
    // Preserve any briefing bubble already rendered in [turns] so the
    // user can keep reading the alert summary while asking follow-ups.
    // Only clear in-flight transcript / response — those belong to a
    // single utterance, not the visible history.
    final preserved = state.turns;
    emit(
      state.copyWith(
        transcript: '',
        response: '',
        turns: preserved,
        surfaceReady: false,
        thinkingTrace: '',
        errorMessage: null,
      ),
    );
    // Reset Gemma's chat history so prior unrelated conversation turns
    // don't leak into the new conversation. The briefing context is
    // *not* lost — [setBriefingContext] keeps the addendum and the
    // newly-rebuilt chat session prefills it as part of the system
    // prompt. Within this conversation the session stays warm across
    // turns so the system prompt prefills only once.
    unawaited(_llm.resetSession());
    if (kDebugMode && _activeBriefingBody != null) {
      debugPrint(
        '[AssistantCubit] new conversation seeded with briefing context '
        '(${_activeBriefingBody!.length} chars)',
      );
    }
    // Run the loop in the background. Errors emit to state; the loop
    // ends on its own when [_conversationActive] flips to false.
    unawaited(_runListenLoop());
  }

  Future<void> stopConversation() async {
    _conversationActive = false;
    _autoConfirmTimer?.cancel();
    await _sttSub?.cancel();
    _sttSub = null;
    await _llmSub?.cancel();
    _llmSub = null;
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

  Future<void> submitTyped(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!_voiceReady) return;
    _conversationActive = true;
    await _respondTo(trimmed, useTriagePath: false);
    _conversationActive = false;
  }

  /// Explicit triage entry — open intake panel for evidence capture.
  void startTriage() {
    _pendingImageJpeg = null;
    _pendingAudioWav = null;
    _lastReport = null;
    _lastUserText = '';
    _lastAssistantText = '';
    _autoConfirmTimer?.cancel();
    emit(state.copyWith(
      stage: AssistantStage.awaitingConfirmation,
      surfaceReady: false,
      transcript: '',
      response: '',
      thinkingTrace: 'Awaiting evidence — attach a photo, voice note, or '
          'text description, then tap Analyse.',
      errorMessage: null,
      intakeOpen: true,
      intakeText: '',
      intakeHasPhoto: false,
      intakeHasAudio: false,
      intakeImagePreview: null,
    ));
  }

  Future<void> confirmSurface() async {
    if (state.stage != AssistantStage.awaitingConfirmation) return;
    _autoConfirmTimer?.cancel();

    final report = _lastReport;
    if (report != null) {
      final id = DateTime.now().toIso8601String();
      final attachments = await _persistAttachments(
        id: id,
        image: _lastUserImage,
        audio: _lastUserAudio,
      );
      final saved = Report(
        id: id,
        userText: _lastUserText,
        assistantText: _lastAssistantText,
        createdAt: DateTime.now(),
        reportJson: jsonEncode(report.toJson()),
        gpsContext: report.gps,
        imagePath: attachments.imagePath,
        audioPath: attachments.audioPath,
      );
      try {
        await _reports.save(saved);
        if (kDebugMode) {
          debugPrint(
            '[Aegis][Cubit] saved report id=$id '
            'severity=${report.severity} '
            'format=${report.format} '
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

    emit(state.copyWith(
      stage: AssistantStage.idle,
      surfaceReady: false,
      intakeOpen: false,
    ));
    if (_conversationActive) {
      unawaited(_runListenLoop());
    }
  }

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

    final priorTurns = state.turns.sublist(0, state.turns.length - 1);
    emit(state.copyWith(
      turns: List.unmodifiable(priorTurns),
      surfaceReady: false,
      thinkingTrace: '',
    ));
    await _respondTo(
      userText,
      useTriagePath: true,
      extraIncidentLog: <String>[
        'previous-attempt-rejected: '
            '${correction ?? "user rejected the generated report; re-evaluate"}',
      ],
    );
  }

  // ---- listen loop / mic capture ------------------------------------

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
        await _respondTo(transcript, useTriagePath: false);
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

    // Mic-open cue. The chat-start cue in [startConversation] only
    // fires once per session; this fires every utterance turn so a
    // long conversation keeps audible feedback when the mic flips
    // hot between turns.
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_cues.playStart());

    emit(state.copyWith(
      stage: AssistantStage.listening,
      transcript: '',
      response: '',
      errorMessage: null,
    ));

    final completer = Completer<String?>();
    // Track the last partial transcript so a 30s auto-stop can return
    // whatever the user said even if VAD never fired its silence-end
    // endpoint (continuous speech, background noise dropping the
    // silence threshold, etc.).
    var latestPartial = '';
    _sttSub = _stt
        .transcribeStream(audioStream, language: _languageCode)
        .listen(
      (update) {
        if (!_conversationActive) return;
        switch (update) {
          case SttPartial(:final text):
            latestPartial = text;
            emit(state.copyWith(transcript: text));
          case SttFinal(:final text):
            latestPartial = text;
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
        if (!completer.isCompleted) completer.complete(latestPartial);
      },
      cancelOnError: true,
    );

    // 30s hard cap on a single listening turn. Without this the mic
    // stays open indefinitely on devices where Silero VAD never
    // commits to an endpoint (ambient hum, continuous speech). Past
    // 30s any captured speech is committed as the final transcript.
    final maxListenTimer = Timer(const Duration(seconds: 30), () {
      if (completer.isCompleted) return;
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] 30s listen cap fired '
            'partial="${latestPartial.length} chars"');
      }
      completer.complete(latestPartial);
    });

    String? captured;
    try {
      captured = await completer.future;
    } on Object catch (e) {
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: e.toString(),
      ));
      captured = null;
    } finally {
      maxListenTimer.cancel();
    }

    await _sttSub?.cancel();
    _sttSub = null;
    try {
      await _recorder.cancel();
    } on Object {
      // best-effort
    }
    // Listening-stopped cue
    // (`assets/sound/listening_end_sound.mp3`).
    unawaited(HapticFeedback.lightImpact());
    unawaited(_cues.playStop());
    return captured;
  }

  // ---- LLM call -----------------------------------------------------

  /// Route a user turn through the right LLM path. `useTriagePath=true`
  /// fires the `render_triage_report` tool call; otherwise streams a
  /// plain chat reply.
  Future<void> _respondTo(
    String transcript, {
    required bool useTriagePath,
    List<String> extraIncidentLog = const <String>[],
    Uint8List? intakeImage,
    Uint8List? intakeAudioWav,
  }) async {
    emit(state.copyWith(
      stage: AssistantStage.thinking,
      response: '',
      surfaceReady: false,
      thinkingTrace: '',
      thinkingForReport: useTriagePath,
    ));
    await _llmSub?.cancel();
    _autoConfirmTimer?.cancel();

    final history = <String>[];
    // Triage reports must be independent of prior triage turns. Each
    // report is graded only on the evidence (image / audio / GPS / text)
    // attached to THIS submission — past reports would bleed
    // observations from unrelated scenes into the current analysis
    // (e.g. "flooding" carrying over into a fire photo). Only the chat
    // path needs conversational replay.
    //
    // `extraIncidentLog` carries reject-feedback ("previous-attempt-
    // rejected: …") for the retry flow — that's intentional and stays.
    if (!useTriagePath) {
      final replay = state.turns.length > _historyTurnsForReplay
          ? state.turns.sublist(state.turns.length - _historyTurnsForReplay)
          : state.turns;
      for (final turn in replay) {
        history.add('user: ${turn.user}');
        final summary = turn.assistant.length > 160
            ? '${turn.assistant.substring(0, 160)}…'
            : turn.assistant;
        history.add('aegis: $summary');
      }
    }
    history.addAll(extraIncidentLog);

    if (useTriagePath) {
      await _runTriage(
        transcript,
        history: history,
        intakeImage: intakeImage,
        intakeAudioWav: intakeAudioWav,
      );
    } else {
      await _runChat(transcript);
    }
  }

  Future<void> _runChat(String transcript) async {
    final responseBuffer = StringBuffer();
    final pending = StringBuffer();
    var spokeAtLeastOne = false;
    _pendingMapQuery = null;
    _pendingMapPlaces = null;
    _pendingMapCenter = null;
    // Tracks the in-flight map-call resolution. Stream.listen's
    // onData callback is *not* awaited by the SDK before onDone fires,
    // so without this gate the listen loop restarts the mic while
    // _resolveMapCall is still hitting sqflite + TTS, the mic catches
    // its own playback, and we end up in an infinite tool-call echo
    // loop. We await this future after the stream closes.
    final mapCallFutures = <Future<void>>[];

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

    final completer = Completer<void>();
    _llmSub = _llm.askStream(transcript).listen(
      (event) {
        switch (event) {
          case ChatTextChunk(:final token):
            if (token.isEmpty) return;
            responseBuffer.write(token);
            pending.write(token);
            emit(state.copyWith(response: responseBuffer.toString()));
            flushSentences();
          case ChatMapCall(:final query):
            if (kDebugMode) {
              debugPrint('[Aegis][Cubit] ChatMapCall $query');
            }
            // Kick off resolution but don't await inside the
            // listener — Stream.listen ignores the returned Future
            // and would fire onDone before this finishes. Track and
            // drain after the stream closes.
            mapCallFutures.add(_resolveMapCall(query));
        }
      },
      onDone: () {
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
      // Wait for any in-flight map-call resolutions to finish before
      // we touch _pendingMapQuery / _pendingMapPlaces below.
      if (mapCallFutures.isNotEmpty) {
        await Future.wait(mapCallFutures);
      }
      // Drain TTS before returning. Two paths queue speech:
      //   • streaming text chunks set [spokeAtLeastOne]
      //   • tool calls (render_map_view) queue TTS inside
      //     [_resolveMapCall]
      // The listen loop restarts mic capture as soon as _runChat
      // returns — if TTS is still playing the mic catches its own
      // playback, STT transcribes it, and Gemma re-fires the tool in
      // an infinite loop. Waiting for whenIdle + a short post-TTS
      // grace gap breaks that.
      if (spokeAtLeastOne || _pendingMapQuery != null) {
        await _tts.whenIdle;
        // Trailing speaker decay + STT VAD warm-up window. Skipping
        // this lets the mic catch the tail end of the system audio
        // through the device's preamp.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      final assistantText = responseBuffer.toString().trim();
      _lastReport = null;
      _lastUserText = transcript.trim();
      _lastAssistantText = assistantText;
      _lastUserImage = null;
      _lastUserAudio = null;

      emit(state.copyWith(
        turns: List.unmodifiable(<ConversationTurn>[
          ...state.turns,
          ConversationTurn(
            user: transcript.trim(),
            assistant: assistantText,
            mapQuery: _pendingMapQuery,
            mapPlaces: _pendingMapPlaces,
            mapCenter: _pendingMapCenter,
          ),
        ]),
        transcript: '',
        response: '',
      ));
      _pendingMapQuery = null;
      _pendingMapPlaces = null;
      _pendingMapCenter = null;
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] _runChat failed: $e');
        debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] _runChat stack');
      }
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

  /// Run the offline POI lookup Gemma asked for, queue the spoken
  /// summary onto the TTS pipeline, and stash the result so [_runChat]
  /// can attach it to the conversation turn. Best-effort — repository
  /// failures emit a warning but never abort the chat reply.
  Future<void> _resolveMapCall(MapViewQuery query) async {
    final repo = _places;
    if (repo == null) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] map call ignored — no PlacesRepository');
      }
      return;
    }
    try {
      // Queue the spoken summary first so it can prefetch + start
      // synthesising while we hit GPS + sqflite. TTS pipeline buffers
      // internally, so the user hears it the moment the map mounts.
      final spoken = query.spokenSummary.trim();
      if (spoken.isNotEmpty) {
        emit(state.copyWith(stage: AssistantStage.speaking));
        unawaited(_tts.enqueue(spoken));
      }
      final center = await _resolveMapCenter();
      if (center == null) {
        if (kDebugMode) {
          debugPrint(
            '[Aegis][Cubit] map call: no usable centre (no GPS, no region)',
          );
        }
        return;
      }
      final hits = await repo.findNearby(
        categories: query.categories,
        center: center,
        radiusKm: query.radiusKm,
      );
      _pendingMapQuery = query;
      _pendingMapPlaces = hits;
      _pendingMapCenter = center;
      if (kDebugMode) {
        debugPrint(
          '[Aegis][Cubit] map call resolved hits=${hits.length} '
          'radius=${query.radiusKm}km',
        );
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] _resolveMapCall failed: $e');
        debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] map stack');
      }
    }
  }

  /// Resolve a usable centre: live GPS fix → onboarding region →
  /// `null`. Uses a tight 3 s GPS timeout to keep chat latency
  /// predictable; offline-only devices fall back to the region picked
  /// during onboarding.
  Future<LatLng?> _resolveMapCenter() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (serviceOn) {
        final permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 3),
            ),
          );
          return LatLng(pos.latitude, pos.longitude);
        }
      }
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] live GPS failed: $e');
      }
    }
    final region = _storage?.selectedRegion;
    if (region == null) return null;
    return LatLng(region.latitude, region.longitude);
  }

  Future<void> _runTriage(
    String transcript, {
    required List<String> history,
    Uint8List? intakeImage,
    Uint8List? intakeAudioWav,
  }) async {
    final gpsContext = await _resolveGpsContext();
    final sw = Stopwatch()..start();
    TriageReport? report;
    try {
      report = await _llm.generateReport(TriageInput(
        userText: transcript,
        incidentLog: history,
        imageJpeg: intakeImage,
        audioWav: intakeAudioWav,
        gpsContext: gpsContext,
      ));
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[Aegis][Cubit] generateReport failed elapsedMs=${sw.elapsedMilliseconds} '
          'error=$e',
        );
        debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] triage stack');
      }
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: e.toString(),
        pendingUserImage: null,
        pendingUserAudio: null,
      ));
      _conversationActive = false;
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] generateReport done elapsedMs=${sw.elapsedMilliseconds} '
        'hasReport=${report != null} '
        'severity=${report?.severity ?? "-"} '
        'format=${report?.format ?? "-"}',
      );
    }

    // Optional spoken summary while the card mounts.
    final spoken = report?.spokenSummary?.trim() ?? '';
    final assistantText = spoken.isNotEmpty
        ? spoken
        : (report?.summary.trim() ?? 'Triage report ready.');
    if (spoken.isNotEmpty) {
      emit(state.copyWith(stage: AssistantStage.speaking));
      try {
        await _tts.enqueue(spoken);
        await _tts.whenIdle;
      } on Object {
        // best-effort
      }
    }

    const placeholder = '(see attached evidence)';
    final committedUserText =
        transcript.trim() == placeholder ? '' : transcript.trim();

    _lastReport = report;
    _lastUserText = committedUserText;
    _lastAssistantText = assistantText;
    _lastUserImage = intakeImage ?? state.pendingUserImage;
    _lastUserAudio = intakeAudioWav;

    emit(state.copyWith(
      turns: List.unmodifiable(<ConversationTurn>[
        ...state.turns,
        ConversationTurn(
          user: committedUserText,
          assistant: assistantText,
          report: report,
          userImage: intakeImage ?? state.pendingUserImage,
          userAudio: intakeAudioWav,
        ),
      ]),
      transcript: '',
      response: assistantText,
      thinkingTrace: assistantText,
      pendingUserImage: null,
      pendingUserAudio: null,
      surfaceReady: report != null,
    ));

    if (report != null) {
      emit(state.copyWith(stage: AssistantStage.awaitingConfirmation));
      // Auto-confirm fallback in case the user walks away. Card always
      // carries an explicit Confirm button, so this just bounds the
      // background hang.
      _autoConfirmTimer = Timer(_autoConfirmTimeout, confirmSurface);
    } else {
      // No tool call — treat as plain reply and move on.
      emit(state.copyWith(stage: AssistantStage.idle));
    }
  }

  // ---- intake actions (called by view) ------------------------------

  void setIntakeText(String text) {
    emit(state.copyWith(intakeText: text.trim()));
  }

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
    emit(state.copyWith(
      intakeHasPhoto: true,
      intakeImagePreview: shrunk,
    ));
    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] intake photo attached '
        'rawBytes=${rawBytes.length} shrunkBytes=${shrunk.length}',
      );
    }
  }

  /// Fires when the view should open its text-entry modal.
  Stream<void> get intakeTextRequests => _intakeTextRequested.stream;
  final StreamController<void> _intakeTextRequested =
      StreamController<void>.broadcast();

  /// Fires when the view should open the photo picker.
  Stream<void> get intakePhotoRequests => _intakePhotoRequested.stream;
  final StreamController<void> _intakePhotoRequested =
      StreamController<void>.broadcast();

  /// User-facing intake feedback (e.g. recording failed).
  Stream<String> get intakeStubRequests => _intakeStubRequested.stream;
  final StreamController<String> _intakeStubRequested =
      StreamController<String>.broadcast();

  void requestIntakeText() => _intakeTextRequested.add(null);
  void requestIntakePhoto() => _intakePhotoRequested.add(null);
  Future<void> requestIntakeAudio() => _captureIntakeAudio();

  Future<void> _captureIntakeAudio() async {
    if (!_voiceReady) {
      _intakeStubRequested.add('Voice models are not ready yet.');
      return;
    }

    // Race-fix: if the chat listen loop already has the recorder hot
    // ("AudioRecorderService.startStream called while already
    // recording"), tear it down before we acquire the mic for intake.
    // This happens when the user taps the triage chip while a normal
    // listening turn is in-flight. We end the conversation first so
    // STT releases the recorder, then proceed.
    if (_conversationActive || _recorder.isRecording) {
      if (kDebugMode) {
        debugPrint(
          '[Aegis][Cubit] intake voice: stopping in-flight listen '
          '(conversationActive=$_conversationActive '
          'recording=${_recorder.isRecording})',
        );
      }
      try {
        await stopConversation();
      } on Object {
        // best-effort
      }
      // Small grace so the underlying mic session fully releases
      // before we ask for it again — flutter_sound's stop() can race
      // with start() on the same isolate.
      await Future<void>.delayed(const Duration(milliseconds: 120));
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

    // Listening cue: tactile + branded chime so user knows mic is hot
    // (`assets/sound/listening_start.mp3`).
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_cues.playStart());

    emit(state.copyWith(stage: AssistantStage.listening));

    Uint8List? wav;
    // Raw-audio capture: no VAD, no endpointing. Triage evidence is
    // often non-speech (ambient sounds, partial sentences, multilingual
    // mixed) that the VAD's silence detector would chop. Capture
    // straight to WAV up to 30s OR until the user taps the mic to
    // stop early ([_intakeAudioCancel] completes from
    // [toggleConversation]).
    _intakeAudioCancel = Completer<void>();
    _intakeAudioActive = true;
    try {
      wav = await _stt.recordRawToWav(
        audioStream,
        maxDuration: const Duration(seconds: 30),
        cancelOn: _intakeAudioCancel!.future,
      );
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Aegis][Cubit] intake voice capture failed: $e');
        debugPrintStack(stackTrace: st, label: '[Aegis][Cubit] intake stack');
      }
    } finally {
      _intakeAudioActive = false;
      _intakeAudioCancel = null;
      try {
        await _recorder.cancel();
      } on Object {
        // best-effort
      }
      // Exit the listening stage immediately so the UI's "Listening…"
      // hint can't linger past capture-end. Stage will be overwritten
      // by the wav-non-null branch below if needed.
      if (state.stage == AssistantStage.listening) {
        emit(state.copyWith(stage: AssistantStage.idle));
      }
      // Capture-complete cue: branded chime + light haptic so user
      // hears the recording closed even when there's no transcript
      // to render (silent / failed capture).
      // (`assets/sound/listening_end_sound.mp3`).
      unawaited(HapticFeedback.lightImpact());
      unawaited(_cues.playStop());
    }

    if (wav == null || wav.isEmpty) {
      _intakeStubRequested.add('Did not catch any audio. Try again.');
      emit(state.copyWith(stage: AssistantStage.awaitingConfirmation));
      return;
    }

    // Reject obviously-silent captures so the LLM doesn't fabricate a
    // triage report out of nothing. RMS below the threshold means the
    // mic only heard background noise.
    if (!_isAudioLoudEnough(wav)) {
      if (kDebugMode) {
        debugPrint(
          '[Aegis][Cubit] intake audio rejected — too quiet '
          '(bytes=${wav.length})',
        );
      }
      _intakeStubRequested.add(
        'The recording was too quiet. Speak closer to the mic and try again.',
      );
      emit(state.copyWith(stage: AssistantStage.awaitingConfirmation));
      return;
    }

    _pendingAudioWav = wav;
    emit(state.copyWith(
      stage: AssistantStage.awaitingConfirmation,
      intakeHasAudio: true,
    ));
    if (kDebugMode) {
      debugPrint(
        '[Aegis][Cubit] intake voice attached wavBytes=${wav.length}',
      );
    }
  }

  Future<void> submitIntake() async {
    final text = state.intakeText.trim();
    final hasImage = _pendingImageJpeg != null;
    final hasAudio = _pendingAudioWav != null && _pendingAudioWav!.isNotEmpty;
    if (text.isEmpty && !hasImage && !hasAudio) {
      _intakeStubRequested.add(
        'Add a description, photo, or voice note before analysing.',
      );
      return;
    }
    final llmUserText = text.isEmpty ? '(see attached evidence)' : text;
    emit(state.copyWith(
      intakeOpen: false,
      surfaceReady: false,
      transcript: text,
      pendingUserImage: _pendingImageJpeg,
      pendingUserAudio: _pendingAudioWav,
    ));
    _conversationActive = true;
    await _respondTo(
      llmUserText,
      useTriagePath: true,
      intakeImage: _pendingImageJpeg,
      intakeAudioWav: _pendingAudioWav,
    );
    _conversationActive = false;
    _pendingImageJpeg = null;
    _pendingAudioWav = null;
  }

  // ---- helpers ------------------------------------------------------

  static Uint8List _shrinkJpeg(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw const FormatException('Unsupported image format');
    }
    // 384px longest edge: at 16x16 patches this lands the image at
    // ~576 patches (24x24 max). The LiteRT-LM vision encoder still
    // pads up to its `max_num_patches: 2520` ceiling regardless of
    // source size, but a smaller JPEG keeps the FFI marshal + image
    // decode path fast and cuts the foreground-thread CPU spike on
    // mid-tier devices. 512 → 384 also shaves ~30% off the encode
    // step (image.copyResize is pure Dart so size matters here too).
    const longestEdge = 384;
    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    final scaled = longest > longestEdge
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? longestEdge : null,
            height: decoded.height > decoded.width ? longestEdge : null,
          )
        : decoded;
    final bytes = img.encodeJpg(scaled, quality: 75);
    return Uint8List.fromList(bytes);
  }

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

  /// RMS-loudness gate for triage audio evidence. Decodes the mono
  /// 16-kHz IEEE-float32 PCM payload from [_encodeWav] (44-byte
  /// header + raw samples) and returns true when the mean amplitude
  /// is loud enough that the recording is worth sending to the LLM.
  /// Threshold tuned to reject pure silence + room hum without
  /// catching whispered speech.
  static const double _silenceRmsThreshold = 0.008;
  static const int _minWavBytes = 44 + 16000 * 4 ~/ 2; // ~0.5s audio
  bool _isAudioLoudEnough(Uint8List wav) {
    if (wav.length <= _minWavBytes) return false;
    // Skip the 44-byte WAV header and treat the remainder as
    // little-endian float32 samples.
    final byteData = ByteData.sublistView(wav, 44);
    final sampleCount = byteData.lengthInBytes ~/ 4;
    if (sampleCount == 0) return false;
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getFloat32(i * 4, Endian.little);
      sumSquares += sample * sample;
    }
    final rms = (sumSquares / sampleCount);
    // Compare squared RMS to avoid an extra sqrt — same monotonic
    // ordering, faster on long clips.
    return rms >= _silenceRmsThreshold * _silenceRmsThreshold;
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
    await _intakeTextRequested.close();
    await _intakePhotoRequested.close();
    await _intakeStubRequested.close();
    await _briefingSub?.cancel();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await _recorder.dispose();
    await _cues.dispose();
    return super.close();
  }
}

