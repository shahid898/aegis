import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/model_catalog.dart';
import '../../../core/voice/model_pack.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/tts_service.dart';

part 'assistant_cubit.freezed.dart';

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
    String? errorMessage,
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
    String? languageCode,
  }) : _recorder = recorder,
       _stt = stt,
       _llm = llm,
       _tts = tts,
       _countryCode = countryCode,
       _languageCode = languageCode,
       super(const AssistantState()) {
    _bootstrap();
  }

  final AudioRecorderService _recorder;
  final SttService _stt;
  final LlmService _llm;
  final TtsService _tts;
  final String _countryCode;
  final String? _languageCode;

  StreamSubscription<SttUpdate>? _sttSub;
  StreamSubscription<String>? _llmSub;
  bool _voiceReady = false;
  bool _conversationActive = false;

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
      final tts = _preferredFor(plan.tts, _languageCode);
      final stt = _preferredFor(plan.stt, _languageCode);
      // VAD is global / language-agnostic: always pick the first pack.
      // The plan should always include exactly one VAD pack today.
      final vad = plan.vad.isNotEmpty ? plan.vad.first : null;
      final llm = plan.llm.isNotEmpty ? plan.llm.first : null;

      if (tts != null) _tts.load(tts).ignore();
      if (stt != null) _stt.setPack(stt);
      if (vad != null) _stt.setVadPack(vad);
      if (llm != null) _llm.setPack(llm);

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
    // Reset transcript/response so the user sees a clean slate.
    emit(state.copyWith(transcript: '', response: '', errorMessage: null));
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

    _sttSub = _stt
        .transcribeStream(audioStream)
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
    await _recorder.dispose();
    return super.close();
  }
}
