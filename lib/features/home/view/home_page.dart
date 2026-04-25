import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

/// Home screen — the single "Ask Aegis" surface.
///
/// - Big circular push-to-talk button (hold to speak, release to ask).
/// - Live transcript of the user's utterance.
/// - Streaming LLM response bubble.
/// - Long-press the button (or double-tap) to trigger the SOS fallback:
///   dial the first saved emergency contact, copy the current location
///   to the clipboard so the user can paste it into a message.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = sl<StorageService>();
    final countryCode = storage.selectedRegion?.countryCode ?? '';

    return BlocProvider<AssistantCubit>(
      create: (_) => AssistantCubit(
        recorder: AudioRecorderService(),
        stt: sl<SttService>(),
        llm: sl<LlmService>(),
        tts: sl<TtsService>(),
        countryCode: countryCode,
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

  String _buttonHint(AssistantStage stage) => switch (stage) {
        AssistantStage.idle => 'Hold to talk · long-press for SOS',
        AssistantStage.preparing => 'Getting ready…',
        AssistantStage.listening => 'Release to send',
        AssistantStage.transcribing => 'Transcribing…',
        AssistantStage.thinking => 'Thinking…',
        AssistantStage.speaking => 'Aegis is speaking',
        AssistantStage.degraded => 'Voice disabled — tap SOS',
        AssistantStage.error => 'Tap to retry',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}

class _TranscriptArea extends StatelessWidget {
  const _TranscriptArea({required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    final hasTranscript = state.transcript.isNotEmpty;
    final hasResponse = state.response.isNotEmpty;

    if (!hasTranscript && !hasResponse) {
      return Center(
        child: Text(
          'Press and hold the button below,\nthen ask Aegis anything.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AegisColors.onSurfaceMuted,
            fontSize: 16,
            height: 1.4,
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (hasTranscript)
          _Bubble(
            label: 'You',
            text: state.transcript,
            align: CrossAxisAlignment.end,
            background: AegisColors.primary.withValues(alpha: 0.10),
          ),
        if (hasResponse) ...[
          const SizedBox(height: 12),
          _Bubble(
            label: 'Aegis',
            text: state.response,
            align: CrossAxisAlignment.start,
            background: Colors.white,
          ),
        ],
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

    return GestureDetector(
      onLongPress: () => _sos(context),
      onTapDown: (_) {
        if (!state.isBusy && !isDegraded) {
          cubit.startListening();
        }
      },
      onTapUp: (_) {
        if (state.stage == AssistantStage.listening) {
          cubit.stopAndAsk();
        }
      },
      onTapCancel: () {
        if (state.stage == AssistantStage.listening) {
          cubit.cancel();
        }
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
              color: startColor.withValues(alpha: isListening ? 0.55 : 0.35),
              blurRadius: isListening ? 68 : 48,
              spreadRadius: isListening ? 10 : 6,
            ),
          ],
        ),
        child: Icon(
          isDegraded ? Icons.sos : (isListening ? Icons.graphic_eq : Icons.mic),
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

    // Stop any ongoing audio before we launch out of the app.
    if (context.mounted) {
      await context.read<AssistantCubit>().cancel();
    }

    // Best-effort: copy current GPS + saved region to the clipboard so the
    // user can paste into a message once the dialer opens.
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
        locationText = 'Emergency. Last known region: '
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
