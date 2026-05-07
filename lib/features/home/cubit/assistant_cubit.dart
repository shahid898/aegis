import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/alert/alert_briefing_sink.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/model_catalog.dart';
import '../../../core/voice/model_pack.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/tts_service.dart';

part 'assistant_cubit.freezed.dart';

/// One completed back-and-forth in a conversation. Appended to
/// [AssistantState.turns] when the model finishes responding to a turn so
/// the UI can render the running history (the previous transcript/response
/// pair otherwise gets clobbered the moment the next utterance starts).
@immutable
class ConversationTurn {
  const ConversationTurn({required this.user, required this.assistant});

  final String user;
  final String assistant;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationTurn &&
          other.user == user &&
          other.assistant == assistant;

  @override
  int get hashCode => Object.hash(user, assistant);

  @override
  String toString() => 'ConversationTurn(user: $user, assistant: $assistant)';

  /// Convenience for building a synthetic system/assistant-only turn.
  /// `user` stays empty so the UI knows there is no user-side bubble
  /// to render — the message arrived from a non-conversational source
  /// (e.g. alert briefing pushed by [AlertBriefingSink]).
  ConversationTurn copyWithAssistant(String text) =>
      ConversationTurn(user: user, assistant: text);
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
    String? errorMessage,
    String? languageCode,
  }) = _AssistantState;

  const AssistantState._();

  bool get isBusy =>
      stage == AssistantStage.preparing ||
      stage == AssistantStage.listening ||
      stage == AssistantStage.transcribing ||
      stage == AssistantStage.thinking ||
      stage == AssistantStage.speaking;

  /// True when the cubit is in the middle of an active conversation —
  /// regardless of which sub-stage (listening / thinking / speaking).
  /// The UI uses this to render a "stop conversation" affordance.
  bool get isConversationActive =>
      stage == AssistantStage.listening ||
      stage == AssistantStage.transcribing ||
      stage == AssistantStage.thinking ||
      stage == AssistantStage.speaking;
}

/// Orchestrates the offline assistant pipeline:
///   mic → STT (streaming partials + endpoint) → LLM → TTS (sentence-chunked).
///
/// One **conversation** can contain many turns. The user taps once to
/// open the mic; the cubit listens continuously, fires the LLM at every
/// recognized endpoint, speaks the response, and immediately reopens the
/// mic for the next utterance. A second tap closes the conversation.
///
/// The cubit owns no UI-facing state beyond [AssistantState]; all model
/// lifecycles belong to the services it is handed. On construction it
/// tries to bind the region's best TTS / STT / LLM packs; if any piece
/// is missing the cubit enters [AssistantStage.degraded].
class AssistantCubit extends Cubit<AssistantState> {
  AssistantCubit({
    required AudioRecorderService recorder,
    required SttService stt,
    required LlmService llm,
    required TtsService tts,
    required String countryCode,
    StorageService? storage,
    AlertBriefingSink? briefingSink,
    String? languageCode,
  }) : _recorder = recorder,
       _stt = stt,
       _llm = llm,
       _tts = tts,
       _countryCode = countryCode,
       _storage = storage,
       _briefingSink = briefingSink,
       _languageCode = languageCode,
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
  final String _countryCode;
  final StorageService? _storage;
  final AlertBriefingSink? _briefingSink;
  String? _languageCode;

  /// Currently-selected ISO-639 language code (mutable — see
  /// [changeLanguage]). Used by the home header to render the active
  /// option in the language dropdown.
  String? get currentLanguageCode => _languageCode;

  StreamSubscription<SttUpdate>? _sttSub;
  StreamSubscription<String>? _llmSub;
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
      // Pick packs that match the user's selected language, not just the
      // first pack in the region plan. India's plan, for example, lists the
      // Hindi voice first, but a user who picked English would otherwise
      // hear the Hindi voice trying to phonemize English text — sounds
      // foreign / wrong. The same applies to the streaming-vs-Whisper STT
      // pick: Hindi speakers should land on Whisper-multilingual instead of
      // the English-only Zipformer.
      // Order TTS packs so the user's preferred language pack is first
      // (becomes the script-ambiguous fallback inside TtsService) but EVERY
      // pack in the region plan is loaded as a resident engine. Without
      // this, a Hindi voice would have to phonemize English replies via
      // espeak-ng-hi — the user perceived that as a "Spanish" accent.
      final ttsPacks = _orderedTtsPacks(plan.tts, _languageCode);
      final stt = _preferredFor(plan.stt, _languageCode);
      // VAD is global / language-agnostic: always pick the first pack.
      // The plan should always include exactly one VAD pack today.
      final vad = plan.vad.isNotEmpty ? plan.vad.first : null;
      final llm = plan.llm.isNotEmpty ? plan.llm.first : null;

      if (ttsPacks.isNotEmpty) _tts.loadAll(ttsPacks).ignore();
      if (stt != null) _stt.setPack(stt);
      if (vad != null) _stt.setVadPack(vad);
      if (llm != null) {
        _llm.setPack(llm);
        // Pin Gemma's reply language to the user's selection so the model
        // can't drift to English when the user is speaking Hindi (and
        // vice-versa) — required for the multi-pack TTS routing above to
        // pick the right voice consistently.
        _llm.setPreferredLanguage(_languageCode);
      }

      // VAD is a hard prerequisite for streaming STT; without it
      // transcribeStream() throws on the first frame, so we treat it as
      // a degraded condition rather than letting the user discover the
      // failure mid-conversation.
      final sttOk = stt != null && vad != null && await _stt.isAvailable();
      final llmOk = llm != null && await _llm.isAvailable();

      if (!sttOk || !llmOk) {
        emit(state.copyWith(stage: AssistantStage.degraded));
        return;
      }

      _voiceReady = true;
      emit(state.copyWith(stage: AssistantStage.idle));
    } on Object catch (e) {
      emit(
        state.copyWith(stage: AssistantStage.error, errorMessage: e.toString()),
      );
    }
  }

  /// Toggle the conversation: tap once to start listening, tap again to
  /// stop. The single entry point keeps the UI button trivial.
  Future<void> toggleConversation() async {
    if (_conversationActive) {
      await stopConversation();
    } else {
      await startConversation();
    }
  }

  /// Open the mic and start the auto-looping listen → respond → listen
  /// pipeline. Safe to call when already running (no-op).
  Future<void> startConversation() async {
    if (!_voiceReady) return;
    if (_conversationActive) return;
    _conversationActive = true;
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

  /// End the conversation. Cancels in-flight STT/LLM/TTS work and
  /// returns the assistant to idle.
  Future<void> stopConversation() async {
    _conversationActive = false;
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
      emit(state.copyWith(stage: AssistantStage.idle));
    }
  }

  /// Compatibility shim — the previous press-to-talk UI called
  /// [startListening]; now it just opens a conversation.
  Future<void> startListening() => startConversation();

  /// Compatibility shim — the previous press-to-talk UI called
  /// [stopAndAsk]; now closes the conversation. Real turn-taking is
  /// driven by endpointing inside the loop.
  Future<void> stopAndAsk() => stopConversation();

  /// Abort the current turn and return to idle.
  Future<void> cancel() => stopConversation();

  // ---- internals ----------------------------------------------------------

  Future<void> _runListenLoop() async {
    try {
      while (_conversationActive) {
        final transcript = await _captureUtterance();
        if (!_conversationActive) break;
        if (transcript == null) {
          // Capture failed (permission, error). Surface the error and
          // exit the loop; the UI will offer a retry tap.
          _conversationActive = false;
          break;
        }
        if (transcript.trim().isEmpty) {
          // Silent capture — go straight back to listening without
          // bothering the LLM.
          continue;
        }
        await _respondTo(transcript);
      }
    } on Object catch (e) {
      _conversationActive = false;
      emit(
        state.copyWith(stage: AssistantStage.error, errorMessage: e.toString()),
      );
      return;
    }

    if (state.stage != AssistantStage.degraded &&
        state.stage != AssistantStage.error) {
      emit(state.copyWith(stage: AssistantStage.idle));
    }
  }

  /// Capture one utterance from the mic. Returns the recognized text on
  /// the first endpoint, `''` if the user said nothing, or `null` if the
  /// capture failed (permission, native error, conversation cancelled).
  Future<String?> _captureUtterance() async {
    if (!_recorder.isOpen) {
      try {
        await _recorder.open();
      } on MicrophonePermissionException {
        emit(
          state.copyWith(
            stage: AssistantStage.error,
            errorMessage: 'Microphone permission is required to talk to Aegis.',
          ),
        );
        return null;
      } on Object catch (e) {
        emit(
          state.copyWith(
            stage: AssistantStage.error,
            errorMessage: e.toString(),
          ),
        );
        return null;
      }
    }

    Stream<Float32List> audioStream;
    try {
      audioStream = await _recorder.startStream();
    } on Object catch (e) {
      emit(
        state.copyWith(stage: AssistantStage.error, errorMessage: e.toString()),
      );
      return null;
    }

    emit(
      state.copyWith(
        stage: AssistantStage.listening,
        transcript: '',
        response: '',
        errorMessage: null,
      ),
    );

    final completer = Completer<String?>();

    // Pin Whisper to the user's selected language. Without this hint,
    // tiny-Whisper auto-detects language per-segment and drifts to wildly
    // wrong codes (Japanese, Arabic) on short utterances or noisy audio.
    // Empty string keeps the auto-detect path for users who haven't picked
    // a language yet.
    _sttSub = _stt
        .transcribeStream(audioStream, language: _languageCode)
        .listen(
          (update) {
            if (!_conversationActive) return;
            switch (update) {
              case SttPartial(:final text):
                emit(state.copyWith(transcript: text));
              case SttFinal(:final text):
                emit(
                  state.copyWith(
                    stage: AssistantStage.transcribing,
                    transcript: text,
                  ),
                );
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
      emit(
        state.copyWith(stage: AssistantStage.error, errorMessage: e.toString()),
      );
      captured = null;
    }

    // Tear down the audio stream — a fresh one is opened for the next
    // turn. This also stops the mic from picking up Aegis's own TTS.
    await _sttSub?.cancel();
    _sttSub = null;
    try {
      await _recorder.cancel();
    } on Object {
      // best-effort
    }

    return captured;
  }

  /// Run the LLM on [transcript] and stream sentences into TTS. Returns
  /// when the response is fully spoken or the conversation is stopped.
  Future<void> _respondTo(String transcript) async {
    emit(state.copyWith(stage: AssistantStage.thinking, response: ''));
    await _llmSub?.cancel();

    // [buffer] is the cumulative response shown in the UI.
    // [pending] is the not-yet-spoken tail — we slice complete sentences
    // off the front and feed them to TTS as the model decodes the rest.
    final buffer = StringBuffer();
    final pending = StringBuffer();
    final completer = Completer<void>();
    var spokeAtLeastOne = false;

    void flushSentences({bool force = false}) {
      final text = pending.toString();
      final cut = force ? text.length : _lastSentenceBoundary(text);
      if (cut <= 0) return;
      final speakable = text.substring(0, cut).trim();
      final remainder = text.substring(cut);
      pending
        ..clear()
        ..write(remainder);
      if (speakable.isEmpty) return;
      if (!spokeAtLeastOne) {
        spokeAtLeastOne = true;
        // Flip stage as soon as the *first* sentence is queued so the
        // UI mic indicator stops pulsing while audio is playing.
        emit(state.copyWith(stage: AssistantStage.speaking));
      }
      unawaited(_tts.enqueue(speakable));
    }

    _llmSub = _llm
        .askStream(transcript)
        .listen(
          (chunk) {
            if (!_conversationActive) return;
            buffer.write(chunk);
            pending.write(chunk);
            emit(state.copyWith(response: buffer.toString()));
            flushSentences();
          },
          onError: (Object e, StackTrace st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          },
          onDone: () {
            // Speak whatever's left even if it didn't end with punctuation.
            flushSentences(force: true);
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

    try {
      await completer.future;
      // Wait for the queue to drain so we don't return to listening
      // while audio is still playing.
      if (spokeAtLeastOne) {
        await _tts.whenIdle;
      }
      // Commit the completed turn to the visible history. Otherwise the
      // next utterance's `transcript: '', response: ''` reset would wipe
      // the prior bubbles off the screen — we'd appear to have no memory
      // even though [LlmService] still does.
      final assistantText = buffer.toString().trim();
      final userText = transcript.trim();
      if (userText.isNotEmpty && assistantText.isNotEmpty) {
        emit(
          state.copyWith(
            turns: List.unmodifiable(<ConversationTurn>[
              ...state.turns,
              ConversationTurn(user: userText, assistant: assistantText),
            ]),
            transcript: '',
            response: '',
          ),
        );
      }
    } on Object catch (e) {
      if (_conversationActive) {
        emit(
          state.copyWith(
            stage: AssistantStage.error,
            errorMessage: e.toString(),
          ),
        );
        _conversationActive = false;
      }
    } finally {
      await _llmSub?.cancel();
      _llmSub = null;
    }
  }

  /// Pick the first pack from [packs] whose [VoiceModelPack.languageCodes]
  /// includes [langCode]. Falls back to `packs.first` when nothing matches
  /// (or when the user hasn't picked a language yet). Returns null only on
  /// an empty list.
  VoiceModelPack? _preferredFor(List<VoiceModelPack> packs, String? langCode) {
    if (packs.isEmpty) return null;
    if (langCode == null || langCode.isEmpty) return packs.first;
    final code = langCode.toLowerCase();
    for (final pack in packs) {
      if (pack.languageCodes.contains(code)) return pack;
    }
    return packs.first;
  }

  /// Return [packs] reordered so the pack that speaks [langCode] is first,
  /// with the rest in their original order. The first pack becomes the
  /// script-ambiguous fallback inside TtsService — keeping every pack in
  /// the list means the engine bank gets fully populated for code-mixed
  /// regions (India, Switzerland, UAE, etc.).
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

  /// Index of the character *after* the last sentence-terminating
  /// punctuation in [text]. Returns 0 if no boundary is present, in
  /// which case the caller keeps buffering until more tokens arrive.
  /// Handles English (`.!?…`), Devanagari (`।`), CJK (`。！？`), and
  /// newlines.
  int _lastSentenceBoundary(String text) {
    if (text.isEmpty) return 0;
    final pattern = RegExp(r'[.!?…।。！？]+["\u201D\u2019\)\]]?\s|\n+');
    var lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      lastEnd = match.end;
    }
    return lastEnd;
  }

  @override
  Future<void> close() async {
    _conversationActive = false;
    await _sttSub?.cancel();
    await _llmSub?.cancel();
    await _briefingSub?.cancel();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await _recorder.dispose();
    return super.close();
  }
}
