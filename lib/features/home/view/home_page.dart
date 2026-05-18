import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/alert/alert_briefing_sink.dart';
import '../../../core/alert/alert_bridge.dart';
import '../../../core/alert/alert_event.dart';
import '../../../core/constants/languages.dart';
import '../../../core/di/injection.dart';
import '../../../core/places/places_repository.dart';
import '../../places/widgets/inline_map_card.dart';
import '../../../models/language_option.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/tts_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../reports/data/reports_repository.dart';
import '../cubit/assistant_cubit.dart';
import '../widgets/aegis_audio_chip.dart';
import '../widgets/triage_intake_panel.dart';
import '../widgets/triage_report_card.dart';

/// Home screen — the single Aegis surface.
///
/// One screen does it all: chat with the assistant, see the streaming
/// transcript, hear the spoken reply, and — when the situation calls
/// for it — render a fixed [TriageReportCard] built from the structured
/// payload Gemma 4 emits via its `render_triage_report` native tool
/// call.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = sl<StorageService>();
    final countryCode = storage.selectedRegion?.countryCode ?? '';
    final languageCode = storage.selectedLanguageCode;

    return BlocProvider<AssistantCubit>(
      create: (_) => AssistantCubit(
        recorder: AudioRecorderService(),
        stt: sl<SttService>(),
        llm: sl<LlmService>(),
        tts: sl<TtsService>(),
        reports: sl<ReportsRepository>(),
        countryCode: countryCode,
        languageCode: languageCode,
        storage: sl<StorageService>(),
        briefingSink: sl<AlertBriefingSink>(),
        places: sl<PlacesRepository>(),
      ),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  late final AssistantCubit _cubit;
  late final List<StreamSubscription<dynamic>> _subs;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<AssistantCubit>();
    _subs = [
      _cubit.intakeTextRequests.listen((_) => _openTextEditor()),
      _cubit.intakePhotoRequests.listen((_) => _openPhotoPicker()),
      _cubit.intakeStubRequests.listen(_showStubMessage),
    ];
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _openPhotoPicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(AppLocalizations.of(context).homeTakePhoto),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(AppLocalizations.of(context).homePickFromGallery),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await _cubit.setIntakePhoto(bytes);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).homePhotoCaptureFailed(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openTextEditor() async {
    final controller = TextEditingController(
      text: _cubit.state.intakeText,
    );
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final viewInsets = MediaQuery.of(sheetContext).viewInsets;
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppLocalizations.of(sheetContext).reportsDescribeScene,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText:
                      AppLocalizations.of(sheetContext).reportsDescribeHint,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(controller.text),
                child: Text(AppLocalizations.of(sheetContext).homeSave),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    _cubit.setIntakeText(result);
  }

  void _showStubMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Debug-only entry point for the SMS-alert pipeline. Tapping fires
      // `AlertBridge.simulate(...)` so we can exercise the wake-app
      // routing pipeline without a real telco. The FAB is dropped in
      // release builds via `kDebugMode`.
      floatingActionButton: const _AlertSimulatorFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: BlocBuilder<AssistantCubit, AssistantState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(state: state),
                  const SizedBox(height: 20),
                  Expanded(child: _TranscriptArea(state: state)),
                  const SizedBox(height: 16),
                  _StatusLine(state: state),
                  const SizedBox(height: 14),
                  Center(child: _PttButton(state: state)),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      _buttonHint(state.stage),
                      style: const TextStyle(
                        color: AegisColors.onSurfaceMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _buttonHint(AssistantStage stage) {
    final l = AppLocalizations.of(context);
    return switch (stage) {
      AssistantStage.idle => l.stageIdle,
      AssistantStage.preparing => l.stagePreparing,
      AssistantStage.listening => l.stageListening,
      AssistantStage.transcribing => l.stageTranscribing,
      AssistantStage.thinking => l.stageThinking,
      AssistantStage.speaking => l.stageSpeaking,
      // Triage report auto-saves on the cubit side (30s auto-confirm
      // timer + the report is already persisted to history at this
      // point), so we suppress the "confirm or reject" prompt under
      // the mic — fall through to the idle hint instead.
      AssistantStage.awaitingConfirmation => l.stageIdle,
      AssistantStage.degraded => l.stageDegraded,
      AssistantStage.error => l.stageError,
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.appName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l.homeSubtitle,
                style: const TextStyle(
                  color: AegisColors.onSurfaceMuted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: l.homeStartTriage,
          onPressed: () => context.read<AssistantCubit>().startTriage(),
          icon: const Icon(Icons.medical_information_outlined),
        ),
        const SizedBox(width: 2),
        IconButton.filledTonal(
          tooltip: l.homeReports,
          onPressed: () => context.push(AppRoute.reports.path),
          icon: const Icon(Icons.assignment_outlined),
        ),
        const SizedBox(width: 5),
        _LanguageDropdown(currentCode: state.languageCode),
      ],
    );
  }
}

/// Compact language switcher anchored to the home header. Renders the
/// currently-selected language at the top of the menu (it's also shown
/// as the trigger label) and the rest of [SupportedLanguages.all]
/// below in their canonical order.
///
/// Selecting a new language calls [AssistantCubit.changeLanguage], which
/// persists the choice, re-pins Gemma's reply language, and re-bootstraps
/// the voice packs so STT/TTS pick the matching voice.
class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({required this.currentCode});
  final String? currentCode;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AssistantCubit>();
    final ordered = _orderedLanguages(currentCode);
    final selected = currentCode == null
        ? null
        : SupportedLanguages.findByCode(currentCode!);
    final triggerLabel = selected?.nativeName ?? 'Language';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AegisColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Change language',
        offset: const Offset(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (code) async {
          if (code == currentCode) return;
          await cubit.changeLanguage(code);
        },
        itemBuilder: (_) => [
          for (final lang in ordered)
            PopupMenuItem<String>(
              value: lang.code,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lang.nativeName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          lang.englishName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AegisColors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lang.code == currentCode)
                    const Icon(
                      Icons.check,
                      size: 18,
                      color: AegisColors.primary,
                    ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 18, color: AegisColors.primary),
              const SizedBox(width: 6),
              Text(
                triggerLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AegisColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: AegisColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Selected language first, rest in canonical order with the
  /// selected entry filtered out so it doesn't appear twice.
  List<LanguageOption> _orderedLanguages(String? selectedCode) {
    final all = SupportedLanguages.all;
    if (selectedCode == null) return all;
    final selected = all.where((l) => l.code == selectedCode).toList();
    if (selected.isEmpty) return all;
    final rest = all.where((l) => l.code != selectedCode).toList();
    return [...selected, ...rest];
  }
}

class _TranscriptArea extends StatefulWidget {
  const _TranscriptArea({required this.state});
  final AssistantState state;

  @override
  State<_TranscriptArea> createState() => _TranscriptAreaState();
}

class _TranscriptAreaState extends State<_TranscriptArea> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(_TranscriptArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.state;
    final next = widget.state;
    final grew = next.turns.length != old.turns.length ||
        next.transcript.length != old.transcript.length ||
        next.response.length != old.response.length ||
        next.intakeOpen != old.intakeOpen ||
        next.surfaceReady != old.surfaceReady ||
        next.stage != old.stage;

    // Detect a newly-appended triage turn so we can fire a follow-up
    // scroll after the report card has had time to lay out. The first
    // scroll snaps to the maxScrollExtent BEFORE TriageReportCard's
    // image / body / actions tree has painted, which leaves the card
    // pinned off-screen on a fresh chat where it's the very first
    // turn. A second scroll one frame later catches the now-correct
    // extent. Subsequent triage turns work fine because the prior
    // assistant bubbles already establish a tall scrollable area.
    final addedTriageTurn = next.turns.length > old.turns.length &&
        next.turns.isNotEmpty &&
        next.turns.last.report != null;

    if (grew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }

    if (addedTriageTurn) {
      // Schedule a follow-up jumpTo after the report card finishes
      // its first layout pass. We chain three deferred scrolls because
      // TriageReportCard contains an evidence image + multi-line body
      // sections whose intrinsic heights only resolve over a couple
      // of frames (image decode, text layout). Cheap to over-call;
      // jumpTo on the same already-extended position is a no-op.
      void scheduleSnap(Duration delay) {
        Future<void>.delayed(delay, () {
          if (!mounted) return;
          if (!_controller.hasClients) return;
          _controller.jumpTo(_controller.position.maxScrollExtent);
        });
      }

      scheduleSnap(const Duration(milliseconds: 80));
      scheduleSnap(const Duration(milliseconds: 240));
      scheduleSnap(const Duration(milliseconds: 600));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final hasTranscript = state.transcript.isNotEmpty;
    final hasResponse = state.response.isNotEmpty;
    final hasHistory = state.turns.isNotEmpty;
    final hasPendingImage = state.pendingUserImage?.isNotEmpty ?? false;
    final hasPendingAudio = state.pendingUserAudio?.isNotEmpty ?? false;
    final hasInflight = hasTranscript ||
        hasResponse ||
        hasPendingImage ||
        hasPendingAudio ||
        state.stage == AssistantStage.thinking;
    final intakeOpen = state.intakeOpen;

    if (!hasInflight && !hasHistory && !intakeOpen) {
      return Center(
        child: Text(
          AppLocalizations.of(context).homeEmptyState,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AegisColors.onSurfaceMuted,
            fontSize: 16,
            height: 1.4,
          ),
        ),
      );
    }

    final inflightCount = hasInflight ? 1 : 0;
    final intakeCount = intakeOpen ? 1 : 0;
    final itemCount = state.turns.length + inflightCount + intakeCount;

    return ListView.builder(
      controller: _controller,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final isFirst = index == 0;
        if (index < state.turns.length) {
          final turn = state.turns[index];
          // Synthetic / system turns (e.g. an alert briefing pushed by
          // [AlertBriefingSink]) have an empty `user` field — the user
          // didn't type anything, the message arrived from the alert
          // pipeline. Render only the assistant-side bubble in that
          // case so the chat doesn't show a bogus "You: …" header.
          final isSystemTurn = turn.user.isEmpty;
          return Padding(
            padding: EdgeInsets.only(top: isFirst ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  _Bubble(
                    label: 'You',
                    text: turn.user,
                    align: CrossAxisAlignment.end,
                    background: AegisColors.primary.withValues(alpha: 0.10),
                    image: turn.userImage,
                    audio: turn.userAudio,
                  ),
                // Triage turns: the TriageReportCard IS the assistant
                // reply — rendering the assistant text bubble too would
                // duplicate the same summary/title in plain text right
                // above the structured card. Only render the assistant
                // text bubble when there's no report attached (normal
                // chat turn) or when the model produced standalone
                // prose alongside the tool call.
                if (turn.report == null) ...[
                  const SizedBox(height: 12),
                  _Bubble(
                    label: 'Aegis',
                    text: turn.assistant,
                    align: CrossAxisAlignment.start,
                    background: Colors.white,
                  ),
                ],
                if (turn.report != null) ...[
                  const SizedBox(height: 12),
                  TriageReportCard(report: turn.report!),
                ],
                if (turn.hasMap) ...[
                  const SizedBox(height: 12),
                  InlineMapCard(
                    query: turn.mapQuery!,
                    places: turn.mapPlaces!,
                    center: turn.mapCenter!,
                    onCall: (phone) async {
                      final uri = Uri(scheme: 'tel', path: phone);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                ],
              ],
            ),
          );
        }

        // In-flight turn first, intake panel after.
        if (hasInflight && index == state.turns.length) {
          final showUser =
              hasTranscript || hasPendingImage || hasPendingAudio;
          final showThinking = state.stage == AssistantStage.thinking;
          return Padding(
            padding: EdgeInsets.only(top: isFirst ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showUser)
                  _Bubble(
                    label: 'You',
                    text: state.transcript,
                    align: CrossAxisAlignment.end,
                    background:
                        AegisColors.primary.withValues(alpha: 0.10),
                    image: state.pendingUserImage,
                    audio: state.pendingUserAudio,
                  ),
                if (showThinking) ...[
                  if (showUser) const SizedBox(height: 12),
                  _ThinkingBubble(forReport: state.thinkingForReport),
                ],
                if (hasResponse) ...[
                  if (showUser) const SizedBox(height: 12),
                  _Bubble(
                    label: 'Aegis',
                    text: state.response,
                    align: CrossAxisAlignment.start,
                    background: Colors.white,
                  ),
                ],
              ],
            ),
          );
        }

        // Intake panel slot.
        return Padding(
          padding: EdgeInsets.only(top: isFirst ? 0 : 16),
          child: BlocBuilder<AssistantCubit, AssistantState>(
            buildWhen: (a, b) =>
                a.intakeText != b.intakeText ||
                a.intakeHasPhoto != b.intakeHasPhoto ||
                a.intakeHasAudio != b.intakeHasAudio ||
                a.intakeImagePreview != b.intakeImagePreview ||
                a.canSubmitIntake != b.canSubmitIntake,
            builder: (context, intakeState) {
              final cubit = context.read<AssistantCubit>();
              return TriageIntakePanel(
                text: intakeState.intakeText,
                hasPhoto: intakeState.intakeHasPhoto,
                hasAudio: intakeState.intakeHasAudio,
                imagePreview: intakeState.intakeImagePreview,
                onTextRequested: cubit.requestIntakeText,
                onPhotoRequested: cubit.requestIntakePhoto,
                onAudioRequested: () => cubit.requestIntakeAudio(),
                onSubmit: () => cubit.submitIntake(),
                canSubmit: intakeState.canSubmitIntake,
              );
            },
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.label,
    required this.text,
    required this.align,
    required this.background,
    this.image,
    this.audio,
  });

  final String label;
  final String text;
  final CrossAxisAlignment align;
  final Color background;
  final Uint8List? image;
  final Uint8List? audio;

  @override
  Widget build(BuildContext context) {
    final hasText = text.isNotEmpty;
    final hasImage = image != null && image!.isNotEmpty;
    final hasAudio = audio != null && audio!.isNotEmpty;
    if (!hasText && !hasImage && !hasAudio) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AegisColors.onSurfaceMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Image.memory(
                      image!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              if (hasImage && (hasAudio || hasText))
                const SizedBox(height: 8),
              if (hasAudio)
                AegisAudioChip(
                  key: ValueKey(audio!.length),
                  wavBytes: audio!,
                ),
              if (hasAudio && hasText) const SizedBox(height: 8),
              if (hasText)
                Text(
                  text,
                  style: const TextStyle(
                    color: AegisColors.onSurface,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble({required this.forReport});

  /// True when the model is generating a structured triage report
  /// (image / audio analysis path). False for plain chat replies. Drives
  /// the status copy so chat doesn't show "Analysing report" while the
  /// model is just answering a yes/no question.
  final bool forReport;

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble> {
  // Tick a stopwatch so the user sees the analysis is alive even when
  // Mali GPU prefill takes 60-90s on multimodal input. The two-line
  // hint also sets expectations — "this can take a minute" — so the
  // user doesn't think the app crashed and force-quit halfway.
  late final Stopwatch _sw;
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds = _sw.elapsed.inSeconds);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sw.stop();
    super.dispose();
  }

  String _statusLine(BuildContext context, int s) {
    final l = AppLocalizations.of(context);
    if (widget.forReport) {
      if (s < 8) return l.thinkingReadingEvidence;
      if (s < 25) return l.thinkingLookingAtImage;
      if (s < 60) return l.thinkingDraftingReport;
      if (s < 120) return l.thinkingStillWorking;
      return l.thinkingFinalisingReport;
    }
    if (s < 6) return l.thinkingGeneric;
    if (s < 20) return l.thinkingComposingReply;
    if (s < 60) return l.thinkingStillThinking;
    return l.thinkingFinalisingReply;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.appName,
          style: const TextStyle(
            color: AegisColors.onSurfaceMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _statusLine(context, _seconds),
                      style: const TextStyle(
                        color: AegisColors.onSurface,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      'Elapsed ${_seconds}s · keep the app open',
                      style: const TextStyle(
                        color: AegisColors.onSurfaceMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Engine warming is a non-error info state — render it on its own
    // info-tinted banner so users don't think it's a failure.
    if (state.engineWarming &&
        state.stage != AssistantStage.degraded &&
        state.stage != AssistantStage.error) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AegisColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.homeEnginePreparing,
                style: const TextStyle(
                  color: AegisColors.onSurface,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final message = switch (state.stage) {
      AssistantStage.degraded => l.homeVoiceDegraded,
      AssistantStage.error => state.errorMessage ?? l.homeSomethingWentWrong,
      _ => null,
    };
    if (message == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AegisColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AegisColors.danger, fontSize: 14),
      ),
    );
  }
}

class _PttButton extends StatelessWidget {
  const _PttButton({required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AssistantCubit>();
    final stage = state.stage;
    final isListening = stage == AssistantStage.listening;
    final isDegraded = stage == AssistantStage.degraded;

    Color startColor;
    Color endColor;
    if (isDegraded) {
      startColor = AegisColors.danger;
      endColor = AegisColors.danger.withValues(alpha: 0.8);
    } else if (isListening) {
      startColor = AegisColors.accent;
      endColor = AegisColors.primaryDark;
    } else {
      startColor = AegisColors.primary;
      endColor = AegisColors.primaryDark;
    }

    final isActiveConversation = state.isConversationActive;
    final showStopGlyph = isActiveConversation;

    return GestureDetector(
      onLongPress: () => _sos(context),
      onTap: () {
        if (isDegraded) return;
        if (state.stage == AssistantStage.preparing) return;
        if (state.stage == AssistantStage.awaitingConfirmation &&
            state.surfaceReady) {
          cubit.confirmSurface();
          return;
        }
        cubit.toggleConversation();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [startColor, endColor],
            radius: 0.95,
          ),
          boxShadow: [
            BoxShadow(
              color: startColor.withValues(
                alpha: isActiveConversation ? 0.55 : 0.35,
              ),
              blurRadius: isActiveConversation ? 44 : 32,
              spreadRadius: isActiveConversation ? 6 : 4,
            ),
          ],
        ),
        child: Icon(
          isDegraded
              ? Icons.sos
              : showStopGlyph
                  ? (isListening ? Icons.graphic_eq : Icons.stop_rounded)
                  : Icons.mic,
          color: Colors.white,
          size: 56,
        ),
      ),
    );
  }

  Future<void> _sos(BuildContext context) async {
    final storage = sl<StorageService>();
    final contacts = storage.emergencyContacts;
    final firstPhone = contacts.isEmpty ? null : contacts.first.phone;

    // Capture context-dependent objects up front so we can use them
    // after the async cancel + GPS wait without the analyzer flagging
    // `use_build_context_synchronously`.
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);

    if (context.mounted) {
      await context.read<AssistantCubit>().cancel();
    }

    String? locationText;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      locationText =
          'Emergency. My location: ${pos.latitude.toStringAsFixed(5)}, '
          '${pos.longitude.toStringAsFixed(5)}';
    } on Exception {
      final region = storage.selectedRegion;
      if (region != null) {
        locationText =
            'Emergency. Last known region: '
            '${region.districtName} (${region.countryCode}).';
      }
    }
    if (locationText != null) {
      await Clipboard.setData(ClipboardData(text: locationText));
    }

    if (firstPhone == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.homeNoEmergencyContact)),
      );
      return;
    }

    final dial = Uri(scheme: 'tel', path: firstPhone);
    final launched = await launchUrl(
      dial,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.homeCouldNotDial(firstPhone))),
      );
    }
  }
}

/// Compact floating action button shown only in debug builds. Opens a
/// sheet with canned alert payloads + a free-text option that drive
/// `AlertBridge.simulate(...)` so we can exercise the wake-app pipeline
/// without a real SMS / SIM. Sized small + pinned bottom-right so it
/// doesn't compete with the mic button for visual weight.
class _AlertSimulatorFab extends StatelessWidget {
  const _AlertSimulatorFab();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'aegis-debug-alert-sim',
      backgroundColor: AegisColors.danger,
      foregroundColor: Colors.white,
      tooltip: 'Simulate alert',
      onPressed: () => _open(context),
      child: const Icon(Icons.bolt, size: 20),
    );
  }

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => const _AlertSimulatorSheet(),
    );
  }
}

class _AlertSimulatorSheet extends StatefulWidget {
  const _AlertSimulatorSheet();

  @override
  State<_AlertSimulatorSheet> createState() => _AlertSimulatorSheetState();
}

class _AlertSimulatorSheetState extends State<_AlertSimulatorSheet> {
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _senderCtrl;
  AlertSeverity _severity = AlertSeverity.critical;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bodyCtrl = TextEditingController(text: _presets.first.body);
    _senderCtrl = TextEditingController(text: _presets.first.sender);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _senderCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(_SimPreset preset) {
    setState(() {
      _bodyCtrl.text = preset.body;
      _senderCtrl.text = preset.sender;
      _severity = preset.severity;
    });
  }

  Future<void> _fire() async {
    if (_busy) return;
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) return;
    final sender = _senderCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _busy = true);
    try {
      final bridge = sl<AlertBridge>();
      await bridge.simulate(
        body: body,
        sender: sender.isEmpty ? null : sender,
        severity: _severity,
      );
      if (!mounted) return;
      navigator.pop();
      // Push the app to the back so the Flutter renderer stops drawing
      // while Gemma's KV-cache prefill + decode hammers the GPU. Without
      // this the home page lags for ~25 s while the LLM decides — with
      // it, the user sees the silent "Aegis is analyzing this alert…"
      // heads-up while the cached engine + foreground service keep the
      // routing pipeline alive in the background. The full-screen-intent
      // re-foregrounds the app the instant the verdict is EMERGENCY.
      unawaited(bridge.moveToBack());
    } on PlatformException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('simulate() failed: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Simulate emergency alert',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Injects a synthetic AlertEvent through the native bridge so '
              'we can exercise the wake-app pipeline without a real SMS.',
              style: TextStyle(
                color: AegisColors.onSurfaceMuted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  ActionChip(
                    label: Text(preset.label),
                    avatar: Icon(preset.icon, size: 18),
                    onPressed: _busy ? null : () => _applyPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _senderCtrl,
              decoration: const InputDecoration(
                labelText: 'Sender',
                hintText: 'e.g. IMD, NDMA, 12345',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Body',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AlertSeverity>(
              initialValue: _severity,
              decoration: const InputDecoration(
                labelText: 'Severity (UI hint only)',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: AlertSeverity.critical,
                  child: Text('Critical (CMAS Presidential / IMD red)'),
                ),
                DropdownMenuItem(
                  value: AlertSeverity.high,
                  child: Text('High'),
                ),
                DropdownMenuItem(
                  value: AlertSeverity.medium,
                  child: Text('Medium'),
                ),
                DropdownMenuItem(value: AlertSeverity.low, child: Text('Low')),
                DropdownMenuItem(
                  value: AlertSeverity.unknown,
                  child: Text('Unknown'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _severity = value);
                    },
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _fire,
              style: FilledButton.styleFrom(
                backgroundColor: AegisColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_busy ? 'Firing…' : 'Fire simulated alert'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preset payloads for the alert simulator. The first one is loaded into
/// the form on open; the others are one-tap chips.
class _SimPreset {
  const _SimPreset({
    required this.label,
    required this.icon,
    required this.sender,
    required this.body,
    required this.severity,
  });

  final String label;
  final IconData icon;
  final String sender;
  final String body;
  final AlertSeverity severity;
}

const List<_SimPreset> _presets = [
  _SimPreset(
    label: 'Cyclone (escalate)',
    icon: Icons.cyclone,
    sender: 'IMD',
    body:
        'Cyclone Biparjoy approaching Mumbai coast. Evacuate to designated '
        'shelters NOW. — IMD',
    severity: AlertSeverity.critical,
  ),
  _SimPreset(
    label: 'Tsunami (escalate)',
    icon: Icons.tsunami,
    sender: 'NDMA',
    body:
        'TSUNAMI WARNING: Move to high ground immediately. Coastal areas '
        'evacuate now.',
    severity: AlertSeverity.critical,
  ),
  _SimPreset(
    label: 'Earthquake drill (dismiss)',
    icon: Icons.science_outlined,
    sender: 'TEST',
    body:
        'Drill alert: this is a TEST message, no action required. Reply STOP '
        'to opt out.',
    severity: AlertSeverity.medium,
  ),
  _SimPreset(
    label: 'Promo decoy (dismiss)',
    icon: Icons.local_offer_outlined,
    sender: 'PROMO',
    body:
        'EMERGENCY SALE 70 percent off. Shop now at example.com — limited '
        'time only.',
    severity: AlertSeverity.unknown,
  ),
];
