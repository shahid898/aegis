import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:genui/genui.dart' as genui;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../widgets/aegis_catalog.dart';
import '../../../app/theme.dart';
import '../../../core/di/injection.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/tts_service.dart';
import '../../reports/data/reports_repository.dart';
import '../cubit/assistant_cubit.dart';

/// Home screen — the single Aegis surface.
///
/// One screen does it all: chat with the assistant, see the streaming
/// transcript, hear the spoken reply, and — when the situation calls for
/// it — interact with a generated A2UI surface (capture-evidence
/// prompts, ICS-209 cards, evacuation plans, etc.) inline in the same
/// chat thread. The agent decides whether to render a surface; the UI
/// renders it inline when present and shows a plain reply bubble when
/// not.
///
/// - Big circular push-to-talk button (tap to start, tap again to stop).
/// - Long-press the button to trigger the SOS fallback: dial the first
///   saved emergency contact, copy the current location to the clipboard.
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
      ),
      child: const _HomeView(),
    );
  }
}

/// Stateful view so we can subscribe to the cubit's intake hooks
/// (text-input modal request + stub-button snackbars). Subscriptions
/// live for the lifetime of the home screen.
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

  /// Open the system image picker. We surface a small action sheet so
  /// the user can choose between camera capture and gallery — common
  /// triage flows want both (the responder shoots a fresh frame; the
  /// survivor attaches a screenshot or saved image).
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
                title: const Text('Take a photo'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Pick from gallery'),
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
      // Cap source-side resolution at 1920px so we don't load a 12MP
      // frame into memory just to scale it back down to 512.
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
          SnackBar(content: Text('Photo capture failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _openTextEditor() async {
    final controller = TextEditingController();
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
                'Describe the scene',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      'eg. "Two-storey house, partial roof collapse, '
                      'one elderly woman trapped near the front door"',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(controller.text),
                child: const Text('Save'),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: BlocBuilder<AssistantCubit, AssistantState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Header(),
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

  String _buttonHint(AssistantStage stage) => switch (stage) {
        AssistantStage.idle => 'Tap to start · long-press for SOS',
        AssistantStage.preparing => 'Getting ready…',
        AssistantStage.listening => 'Listening… tap to stop',
        AssistantStage.transcribing => 'Transcribing…',
        AssistantStage.thinking => 'Thinking… tap to interrupt',
        AssistantStage.speaking => 'Aegis is speaking · tap to stop',
        AssistantStage.awaitingConfirmation =>
          'Review the card above · confirm or reject',
        AssistantStage.degraded => 'Voice disabled — tap SOS',
        AssistantStage.error => 'Tap to retry',
      };
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aegis',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Offline. Ready.',
                style: TextStyle(
                  color: AegisColors.onSurfaceMuted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Start triage',
          onPressed: () => context.read<AssistantCubit>().startTriage(),
          icon: const Icon(Icons.medical_information_outlined),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Reports',
          onPressed: () => context.push(AppRoute.reports.path),
          icon: const Icon(Icons.assignment_outlined),
        ),
      ],
    );
  }
}

/// Renders both the running [AssistantState.turns] history and the
/// in-flight transcript / response bubbles. Owns its own
/// [ScrollController] so we pin to the most recent bubble as the
/// model streams. When the agent emits a surface for the in-flight
/// turn, the live `genui.Surface` widget renders inline in place of
/// the streaming text bubble.
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
    final grew =
        next.turns.length != old.turns.length ||
        next.transcript.length != old.transcript.length ||
        next.response.length != old.response.length ||
        next.surfaceReady != old.surfaceReady ||
        next.stage != old.stage;
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
    final hasSurface = state.surfaceReady;
    final isVerifying = state.stage == AssistantStage.awaitingConfirmation;
    final hasInflight = hasTranscript ||
        hasResponse ||
        hasSurface ||
        (state.pendingUserImage?.isNotEmpty ?? false) ||
        (state.pendingUserAudio?.isNotEmpty ?? false) ||
        state.stage == AssistantStage.thinking;

    if (!hasInflight && !hasHistory) {
      return const Center(
        child: Text(
          'Tap the button below to start a\nconversation with Aegis.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AegisColors.onSurfaceMuted,
            fontSize: 16,
            height: 1.4,
          ),
        ),
      );
    }

    final itemCount = state.turns.length + (hasInflight ? 1 : 0);

    return ListView.builder(
      controller: _controller,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final isFirst = index == 0;
        if (index < state.turns.length) {
          final turn = state.turns[index];
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
                const SizedBox(height: 12),
                _Bubble(
                  label: 'Aegis',
                  text: turn.assistant,
                  align: CrossAxisAlignment.start,
                  background: Colors.white,
                ),
                if (turn.hadSurface) ...[
                  const SizedBox(height: 8),
                  _SurfaceArchivedChip(turn: turn),
                ],
              ],
            ),
          );
        }

        // In-flight turn: streaming transcript, partial response, and/or
        // a live A2UI surface. The agent may emit any subset.
        final hasPendingImage = (state.pendingUserImage?.isNotEmpty ?? false);
        final hasPendingAudio = (state.pendingUserAudio?.isNotEmpty ?? false);
        final showUser = hasTranscript || hasPendingImage || hasPendingAudio;
        final showThinking = state.stage == AssistantStage.thinking &&
            !hasResponse &&
            !hasSurface;
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
                  background: AegisColors.primary.withValues(alpha: 0.10),
                  image: state.pendingUserImage,
                  audio: state.pendingUserAudio,
                ),
              if (showThinking) ...[
                if (showUser) const SizedBox(height: 12),
                const _ThinkingBubble(),
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
              if (hasSurface) ...[
                const SizedBox(height: 12),
                const _LiveSurface(),
              ],
              if (isVerifying) ...[
                const SizedBox(height: 12),
                _ThinkingTraceDrawer(trace: state.thinkingTrace),
                // Host-owned reject/confirm row is only rendered when the
                // surface itself doesn't already carry a ConfirmActionBar.
                // The agent's prompt mandates a ConfirmActionBar, so 99% of
                // turns this branch is skipped — keeping it as a fallback so
                // a misbehaving model that forgets the action bar still
                // leaves the user a way out.
                if (!hasSurface) ...[
                  const SizedBox(height: 12),
                  const _VerificationActions(),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Live A2UI surface for the in-flight turn. Bound to the cubit's
/// [genui.SurfaceController] via `contextFor(surfaceId)`. Cards render
/// progressively as Gemma 4 streams JSON envelopes — the user sees a
/// damage card pop in, then a casualty card, then a confirm bar, in
/// real time.
class _LiveSurface extends StatelessWidget {
  const _LiveSurface();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AssistantCubit>().surfaceController;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
        ),
      ),
      child: genui.Surface(
        surfaceContext: controller.contextFor(AssistantCubit.surfaceId),
      ),
    );
  }
}

/// Tappable chip on a past turn that emitted a surface. Tapping opens
/// a modal that replays the captured A2UI messages into a private
/// SurfaceController so the user can re-inspect what was rendered at
/// the time. We don't keep the historical surface live in the main
/// controller (it's already been overwritten by later turns) — instead
/// we re-mount the messages on demand.
class _SurfaceArchivedChip extends StatelessWidget {
  const _SurfaceArchivedChip({required this.turn});

  final ConversationTurn turn;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showArchivedSurface(context, turn),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AegisColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.dashboard_customize_outlined, size: 14),
              SizedBox(width: 6),
              Text(
                'Action card · tap to view',
                style: TextStyle(
                  fontSize: 12,
                  color: AegisColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showArchivedSurface(
    BuildContext context,
    ConversationTurn turn,
  ) async {
    final cubit = context.read<AssistantCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _ArchivedSurfaceSheet(
        catalog: cubit.catalog,
        messages: turn.surfaceMessages,
        userText: turn.user,
      ),
    );
  }
}

/// Modal that mounts a private [genui.SurfaceController], replays the
/// captured A2UI messages from a past turn, and renders the resulting
/// surface inside a [genui.Surface] widget. The controller is owned by
/// the modal — disposed when the sheet closes — so the live home
/// surface controller stays untouched.
class _ArchivedSurfaceSheet extends StatefulWidget {
  const _ArchivedSurfaceSheet({
    required this.catalog,
    required this.messages,
    required this.userText,
  });

  final genui.Catalog catalog;
  final List<genui.A2uiMessage> messages;
  final String userText;

  @override
  State<_ArchivedSurfaceSheet> createState() => _ArchivedSurfaceSheetState();
}

class _ArchivedSurfaceSheetState extends State<_ArchivedSurfaceSheet> {
  late final genui.SurfaceController _controller;
  String? _surfaceId;

  @override
  void initState() {
    super.initState();
    _controller = genui.SurfaceController(catalogs: [widget.catalog]);
    for (final message in widget.messages) {
      _controller.handleMessage(message);
      // Capture the first createSurface's id so the Surface widget
      // can subscribe to the right ValueListenable. We can't reuse the
      // live surfaceId because that's bound to the active controller.
      if (_surfaceId == null && message is genui.CreateSurface) {
        _surfaceId = message.surfaceId;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'You: "${widget.userText}"',
                  style: TextStyle(
                    color: AegisColors.onSurfaceMuted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              if (_surfaceId == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      '(no surface to replay)',
                      style: TextStyle(color: AegisColors.onSurfaceMuted),
                    ),
                  ),
                )
              else
                genui.Surface(
                  surfaceContext: _controller.contextFor(_surfaceId!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingTraceDrawer extends StatefulWidget {
  const _ThinkingTraceDrawer({required this.trace});

  final String trace;

  @override
  State<_ThinkingTraceDrawer> createState() => _ThinkingTraceDrawerState();
}

class _ThinkingTraceDrawerState extends State<_ThinkingTraceDrawer> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('Reasoning trace'),
            subtitle: Text(_open
                ? 'Tap to hide'
                : 'Inspect why Aegis composed this card'),
            trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _open = !_open),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                widget.trace.isEmpty ? '(no trace recorded)' : widget.trace,
                style: const TextStyle(
                  color: AegisColors.onSurfaceMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VerificationActions extends StatelessWidget {
  const _VerificationActions();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AssistantCubit>();
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => cubit.rejectSurface(),
            icon: const Icon(Icons.refresh),
            label: const Text('Reject'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: cubit.confirmSurface,
            icon: const Icon(Icons.check),
            label: const Text('Confirm'),
          ),
        ),
      ],
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

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aegis',
          style: TextStyle(
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
            children: const [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text(
                'Analysing your report…',
                style: TextStyle(
                  color: AegisColors.onSurface,
                  fontSize: 15,
                  height: 1.3,
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
    final message = switch (state.stage) {
      AssistantStage.degraded =>
        'Voice models are not installed. You can still use SOS.',
      AssistantStage.error => state.errorMessage ?? 'Something went wrong.',
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
        cubit.toggleConversation();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 220,
        height: 220,
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
              blurRadius: isActiveConversation ? 68 : 48,
              spreadRadius: isActiveConversation ? 10 : 6,
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
          size: 88,
        ),
      ),
    );
  }

  Future<void> _sos(BuildContext context) async {
    final storage = sl<StorageService>();
    final contacts = storage.emergencyContacts;
    final firstPhone = contacts.isEmpty ? null : contacts.first.phone;

    final messenger = ScaffoldMessenger.of(context);

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
        const SnackBar(
          content: Text('No emergency contact saved. Add one in settings.'),
        ),
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
        SnackBar(content: Text('Could not open dialer for $firstPhone.')),
      );
    }
  }
}
