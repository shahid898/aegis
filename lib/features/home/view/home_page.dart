import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:genui/genui.dart' as genui;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/di/injection.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/audio_recorder_service.dart';
import '../../../core/voice/llm_service.dart';
import '../../../core/voice/stt_service.dart';
import '../../../core/voice/tts_service.dart';
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
        countryCode: countryCode,
        languageCode: languageCode,
      ),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Aegis', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        const Text(
          'Offline. Ready.',
          style: TextStyle(color: AegisColors.onSurfaceMuted, fontSize: 14),
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
    final hasInflight = hasTranscript || hasResponse || hasSurface;

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
                  const _SurfaceArchivedChip(),
                ],
              ],
            ),
          );
        }

        // In-flight turn: streaming transcript, partial response, and/or
        // a live A2UI surface. The agent may emit any subset.
        return Padding(
          padding: EdgeInsets.only(top: isFirst ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasTranscript)
                _Bubble(
                  label: 'You',
                  text: state.transcript,
                  align: CrossAxisAlignment.end,
                  background: AegisColors.primary.withValues(alpha: 0.10),
                ),
              if (hasResponse) ...[
                if (hasTranscript) const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                const _VerificationActions(),
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

class _SurfaceArchivedChip extends StatelessWidget {
  const _SurfaceArchivedChip();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AegisColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined, size: 14),
            SizedBox(width: 6),
            Text(
              'Action card was shown',
              style: TextStyle(
                fontSize: 12,
                color: AegisColors.onSurface,
              ),
            ),
          ],
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
  });

  final String label;
  final String text;
  final CrossAxisAlignment align;
  final Color background;

  @override
  Widget build(BuildContext context) {
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
          child: Text(
            text,
            style: const TextStyle(
              color: AegisColors.onSurface,
              fontSize: 16,
              height: 1.35,
            ),
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
