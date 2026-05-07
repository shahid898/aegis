import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/alert/alert_briefing_sink.dart';
import '../../../core/alert/alert_bridge.dart';
import '../../../core/alert/alert_event.dart';
import '../../../core/constants/languages.dart';
import '../../../core/di/injection.dart';
import '../../../models/language_option.dart';
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
    final languageCode = storage.selectedLanguageCode;

    return BlocProvider<AssistantCubit>(
      create: (_) => AssistantCubit(
        recorder: AudioRecorderService(),
        stt: sl<SttService>(),
        llm: sl<LlmService>(),
        tts: sl<TtsService>(),
        countryCode: countryCode,
        languageCode: languageCode,
        storage: sl<StorageService>(),
        briefingSink: sl<AlertBriefingSink>(),
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
      // Debug-only entry point for the SMS-alert pipeline. Tapping fires
      // `AlertBridge.simulate(...)` so we can exercise FunctionGemma routing
      // and the PENDING/CONFIRMED state machine without a real telco. The FAB
      // is dropped in release builds via `kDebugMode`.
      floatingActionButton: kDebugMode ? const _AlertSimulatorFab() : null,
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
    AssistantStage.idle => 'Tap to start · long-press for SOS',
    AssistantStage.preparing => 'Getting ready…',
    AssistantStage.listening => 'Listening… tap to stop',
    AssistantStage.transcribing => 'Transcribing…',
    AssistantStage.thinking => 'Thinking… tap to interrupt',
    AssistantStage.speaking => 'Aegis is speaking · tap to stop',
    AssistantStage.degraded => 'Voice disabled — tap SOS',
    AssistantStage.error => 'Tap to retry',
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aegis', style: Theme.of(context).textTheme.headlineMedium),
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

/// Renders both the running [AssistantState.turns] history and the
/// in-flight transcript / response bubbles. Owns its own [ScrollController]
/// so we can pin the view to the most recent bubble as the model streams.
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
        next.response.length != old.response.length;
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
    final hasInflight = hasTranscript || hasResponse;

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
                if (!isSystemTurn) ...[
                  _Bubble(
                    label: 'You',
                    text: turn.user,
                    align: CrossAxisAlignment.end,
                    background: AegisColors.primary.withValues(alpha: 0.10),
                  ),
                  const SizedBox(height: 12),
                ],
                _Bubble(
                  label: 'Aegis',
                  text: turn.assistant,
                  align: CrossAxisAlignment.start,
                  background: Colors.white,
                ),
              ],
            ),
          );
        }

        // In-flight turn: streaming transcript and/or partial response.
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
            ],
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

/// Floating action button shown only in debug builds. Opens a sheet with
/// canned alert payloads + a free-text option that drive
/// `AlertBridge.simulate(...)` so we can exercise the wake-app pipeline
/// without a real SMS / SIM.
class _AlertSimulatorFab extends StatelessWidget {
  const _AlertSimulatorFab();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'aegis-debug-alert-sim',
      backgroundColor: AegisColors.danger,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.bolt),
      label: const Text('Simulate alert'),
      onPressed: () => _open(context),
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
      final result = await sl<AlertBridge>().simulate(
        body: body,
        sender: sender.isEmpty ? null : sender,
        severity: _severity,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == null
                ? 'simulate() returned null — check the native logs.'
                : 'Simulated alert ${result.id} delivered. '
                      'Watch logcat for the FunctionGemma verdict.',
          ),
        ),
      );
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
              'Injects a synthetic AlertEvent through the native bridge — '
              'exercises FunctionGemma + the PENDING/CONFIRMED siren state '
              'machine without a real SMS.',
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
