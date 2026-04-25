import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/model_catalog.dart';
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
}

/// Orchestrates the offline assistant pipeline:
///   mic → STT → LLM → TTS.
///
/// The cubit owns no UI-facing state beyond [AssistantState]; all model
/// lifecycles belong to the services it is handed. On construction it
/// tries to bind the region's best TTS / STT / LLM packs; if any piece
/// is missing the cubit enters [AssistantStage.degraded] and refuses to
/// start a recording, so the home screen can show a "set up voice"
/// affordance instead of a broken mic.
class AssistantCubit extends Cubit<AssistantState> {
  AssistantCubit({
    required AudioRecorderService recorder,
    required SttService stt,
    required LlmService llm,
    required TtsService tts,
    required String countryCode,
  })  : _recorder = recorder,
        _stt = stt,
        _llm = llm,
        _tts = tts,
        _countryCode = countryCode,
        super(const AssistantState()) {
    _bootstrap();
  }

  final AudioRecorderService _recorder;
  final SttService _stt;
  final LlmService _llm;
  final TtsService _tts;
  final String _countryCode;

  StreamSubscription<String>? _llmSub;
  bool _voiceReady = false;

  Future<void> _bootstrap() async {
    emit(state.copyWith(stage: AssistantStage.preparing));
    try {
      final plan = ModelCatalog.planFor(_countryCode);
      final tts = plan.tts.isNotEmpty ? plan.tts.first : null;
      final stt = plan.stt.isNotEmpty ? plan.stt.first : null;
      final llm = plan.llm.isNotEmpty ? plan.llm.first : null;

      if (tts != null) _tts.load(tts).ignore();
      if (stt != null) _stt.setPack(stt);
      if (llm != null) _llm.setPack(llm);

      final sttOk = stt != null && await _stt.isAvailable();
      final llmOk = llm != null && await _llm.isAvailable();

      if (!sttOk || !llmOk) {
        emit(state.copyWith(stage: AssistantStage.degraded));
        return;
      }

      _voiceReady = true;
      emit(state.copyWith(stage: AssistantStage.idle));
    } on Object catch (e) {
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Begin capturing the microphone. Call [stopAndAsk] to end the turn.
  Future<void> startListening() async {
    if (!_voiceReady) return;
    if (state.stage != AssistantStage.idle &&
        state.stage != AssistantStage.error) {
      return;
    }
    try {
      await _tts.stop();
      if (!_recorder.isOpen) {
        await _recorder.open();
      }
      await _recorder.start();
      emit(state.copyWith(
        stage: AssistantStage.listening,
        transcript: '',
        response: '',
        errorMessage: null,
      ));
    } on MicrophonePermissionException {
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: 'Microphone permission is required to talk to Aegis.',
      ));
    } on Object catch (e) {
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Stop the recording, transcribe, and ask the LLM. Streams the
  /// response into state so the UI can render tokens as they arrive.
  Future<void> stopAndAsk() async {
    if (state.stage != AssistantStage.listening) {
      // If we were never listening, nothing to stop.
      return;
    }

    emit(state.copyWith(stage: AssistantStage.transcribing));

    try {
      final samples = await _recorder.stop();
      if (samples.isEmpty) {
        emit(state.copyWith(stage: AssistantStage.idle));
        return;
      }

      final transcript = await _stt.transcribe(samples);
      emit(state.copyWith(
        stage: AssistantStage.thinking,
        transcript: transcript,
      ));

      if (transcript.isEmpty) {
        emit(state.copyWith(stage: AssistantStage.idle));
        return;
      }

      await _llmSub?.cancel();
      final buffer = StringBuffer();
      final completer = Completer<String>();

      _llmSub = _llm.askStream(transcript).listen(
        (chunk) {
          buffer.write(chunk);
          emit(state.copyWith(response: buffer.toString()));
        },
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        },
        cancelOnError: true,
      );

      final full = await completer.future;
      await _speak(full);
    } on Object catch (e) {
      emit(state.copyWith(
        stage: AssistantStage.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Abort the current turn and return to idle.
  Future<void> cancel() async {
    await _llmSub?.cancel();
    _llmSub = null;
    await _recorder.cancel();
    await _tts.stop();
    emit(state.copyWith(stage: AssistantStage.idle));
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) {
      emit(state.copyWith(stage: AssistantStage.idle));
      return;
    }
    emit(state.copyWith(stage: AssistantStage.speaking));
    try {
      await _tts.speak(text);
    } on Object {
      // TTS is a nice-to-have — the response text is already on screen.
    }
    emit(state.copyWith(stage: AssistantStage.idle));
  }

  @override
  Future<void> close() async {
    await _llmSub?.cancel();
    await _recorder.dispose();
    return super.close();
  }
}
