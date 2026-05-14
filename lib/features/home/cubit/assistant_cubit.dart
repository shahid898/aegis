import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/model_catalog.dart';
import '../../../core/voice/model_pack.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/triage_input.dart';
import '../../../core/voice/triage_report.dart';
import '../../../core/voice/tts_service.dart';
import '../../reports/data/report.dart';
import '../../reports/data/reports_repository.dart';

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
  });

  final String user;
  final String assistant;

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
        super(const AssistantState()) {
    _bootstrap();
  }

  /// Cap on prior turns we replay into the per-turn `incidentLog`.
  static const int _historyTurnsForReplay = 4;

  final AudioRecorderService _recorder;
  final SttService _stt;
  final LlmService _llm;
  final TtsService _tts;
  final ReportsRepository _reports;
  final String _countryCode;
  final String? _languageCode;
  final Duration _autoConfirmTimeout;

  Uint8List? _pendingImageJpeg;
  Uint8List? _pendingAudioWav;
  TriageReport? _lastReport;
  String _lastUserText = '';
  Uint8List? _lastUserImage;
  Uint8List? _lastUserAudio;
  String _lastAssistantText = '';

  StreamSubscription<SttUpdate>? _sttSub;
  StreamSubscription<String>? _llmSub;
  Timer? _autoConfirmTimer;
  bool _voiceReady = false;
  bool _conversationActive = false;

  Future<void> _bootstrap() async {
    emit(state.copyWith(stage: AssistantStage.preparing));
    try {
      final plan = ModelCatalog.planFor(_countryCode);
      final ttsPacks = _orderedTtsPacks(plan.tts, _languageCode);
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
      (chunk) {
        if (chunk.isEmpty) return;
        responseBuffer.write(chunk);
        pending.write(chunk);
        emit(state.copyWith(response: responseBuffer.toString()));
        flushSentences();
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
      if (spokeAtLeastOne) await _tts.whenIdle;

      final assistantText = responseBuffer.toString().trim();
      _lastReport = null;
      _lastUserText = transcript.trim();
      _lastAssistantText = assistantText;
      _lastUserImage = null;
      _lastUserAudio = null;

      emit(state.copyWith(
        turns: List.unmodifiable(<ConversationTurn>[
          ...state.turns,
          ConversationTurn(user: transcript.trim(), assistant: assistantText),
        ]),
        transcript: '',
        response: '',
      ));
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
    await _recorder.dispose();
    return super.close();
  }
}

