import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/voice/llm_service.dart';
import '../../../../core/voice/stt_service.dart';
import '../../../../core/voice/tts_service.dart';
import '../../../../l10n/generated/app_localizations.dart';

class ReadyPage extends StatefulWidget {
  const ReadyPage({super.key});

  @override
  State<ReadyPage> createState() => _ReadyPageState();
}

class _ReadyPageState extends State<ReadyPage> {
  bool _busy = false;

  /// Hand off to the home shell. Marks onboarding complete, then
  /// pre-touches the lazy voice singletons so their native bindings
  /// initialize while the user sees an explicit spinner. Without this
  /// pre-warm, the first cold `sl<SttService>()` / `sl<TtsService>()`
  /// from HomePage's `BlocProvider.create` happens silently during
  /// the route transition — the user sees a frozen Start button for
  /// 1-2 s. Pre-touching here moves the freeze under a loading
  /// indicator instead.
  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await sl<StorageService>().setOnboardingCompleted(true);
      // Force lazy-singleton construction off the main build path.
      // Each `sl<>()` call returns immediately if already instantiated
      // (LlmService is eagerly touched in DI boot), so the cost here
      // is the first SttService + TtsService construction — sherpa
      // method-channel handshakes that would otherwise stall
      // HomePage's first frame.
      sl<LlmService>();
      sl<SttService>();
      sl<TtsService>();
      // Yield to the next frame so the spinner actually paints before
      // we tear down this page. Without this, navigation can preempt
      // the rebuild and the user never sees feedback.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      context.go(AppRoute.home.path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: AegisColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AegisColors.primary.withValues(alpha: 0.35),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 72,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                l.readyTitle,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 12),
              Text(
                l.readyBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: AegisColors.onSurfaceMuted,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _start,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(l.actionStart),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
