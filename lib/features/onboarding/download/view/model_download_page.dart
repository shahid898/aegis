import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/places/onboarding_places_downloader.dart';
import '../../../../core/places/tile_cache_downloader.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/voice/model_pack_repository.dart';
import '../../../../core/voice/model_registry.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/model_download_cubit.dart';

class ModelDownloadPage extends StatelessWidget {
  const ModelDownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final region = sl<StorageService>().selectedRegion;
    final country = region?.countryCode ?? '';
    return BlocProvider(
      create: (_) => ModelDownloadCubit(
        countryCode: country,
        repository: sl<ModelPackRepository>(),
        registry: sl<ModelRegistry>(),
        region: region,
        placesDownloader: OnboardingPlacesDownloader(),
        tileCacheDownloader: TileCacheDownloader(),
      )..start(),
      child: const _DownloadView(),
    );
  }
}

class _DownloadView extends StatelessWidget {
  const _DownloadView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.downloadTitle)),
      body: SafeArea(
        child: BlocConsumer<ModelDownloadCubit, ModelDownloadState>(
          listenWhen: (prev, next) => prev.status != next.status,
          listener: (context, state) {
            if (state.status == DownloadStatus.completed) {
              _goNext(context);
            }
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.downloadHeading,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.downloadBody,
                    style: const TextStyle(
                      color: AegisColors.onSurfaceMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Time-expectation banner. Sets the user up so a long
                  // wait feels deliberate instead of broken. Tinted
                  // surface so it reads as info, not warning.
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: AegisColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.schedule_outlined,
                            size: 18, color: AegisColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.downloadFirstInstallNote,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: AegisColors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Centered linear-progress stack. The per-pack ListView
                  // was removed because it surfaced internal pack ids
                  // (`llm-gemma-4-…`, `tts-piper-…`) that mean nothing to
                  // a non-engineer user. One progress bar + an optional
                  // places/tiles status line is enough signal.
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _OverallProgress(state: state),
                            if (state.placesProgressMessage.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _SecondaryProgressRow(
                                message: state.placesProgressMessage,
                                inFlight: state.status ==
                                    DownloadStatus.seedingPlaces,
                              ),
                            ],
                            if (state.tilesProgressMessage.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _SecondaryProgressRow(
                                message: state.tilesProgressMessage,
                                inFlight: state.status ==
                                    DownloadStatus.seedingTiles,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Actions(state: state),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _goNext(BuildContext context) {
    // Small delay so users see the "Completed" state before transition.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!context.mounted) return;
      context.go(AppRoute.accessibility.path);
    });
  }
}

class _OverallProgress extends StatelessWidget {
  const _OverallProgress({required this.state});
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pct = (state.overallFraction * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Big percentage readout — the primary thing the user wants to
        // know while they wait. Aligned center for visual balance.
        Center(
          child: Text(
            '$pct%',
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w700,
              color: AegisColors.primary,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: state.overallFraction == 0 ? null : state.overallFraction,
          minHeight: 12,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            l.downloadPercentComplete(pct.toString()),
            style: const TextStyle(
              color: AegisColors.onSurfaceMuted,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact "places / tiles" status row. Shows a spinner while the
/// step is in-flight, a checkmark afterwards. Centered so it sits
/// under the main progress bar without competing with it.
class _SecondaryProgressRow extends StatelessWidget {
  const _SecondaryProgressRow({
    required this.message,
    required this.inFlight,
  });

  final String message;
  final bool inFlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (inFlight)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          const Icon(Icons.check_circle_outline,
              size: 16, color: AegisColors.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AegisColors.onSurfaceMuted,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// _PackTile + _StatusIcon were removed when the per-pack list view was
// replaced by a single centered progress bar. Internal pack ids
// (`llm-gemma-4-…`, `tts-piper-…`) were leaking through `pack.displayName`
// and adding no user-meaningful signal beyond the overall percentage.

class _Actions extends StatelessWidget {
  const _Actions({required this.state});
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Failure: surface error + Retry. No skip — model packs are
    // mandatory for offline operation. User retries (Range-resumes
    // from where it stopped) or backgrounds the app.
    if (state.status == DownloadStatus.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AegisColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.errorMessage ?? l.downloadFailed,
                  style: const TextStyle(color: AegisColors.danger),
                ),
                const SizedBox(height: 4),
                Text(
                  l.downloadCheckConnection,
                  style: const TextStyle(
                    color: AegisColors.danger,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.read<ModelDownloadCubit>().start(),
            icon: const Icon(Icons.refresh),
            label: Text(l.actionRetry),
          ),
        ],
      );
    }

    // Completion: full-width Continue. Caller's listener auto-navigates
    // after a short delay so this button is mostly a fallback for the
    // rare race where the listener missed the state flip.
    if (state.allInstalled || state.status == DownloadStatus.completed) {
      return FilledButton(
        onPressed: () => context.go(AppRoute.accessibility.path),
        child: Text(l.actionContinue),
      );
    }

    // In-flight: disabled-Continue + mandatory note. We deliberately
    // do NOT expose a Skip button. Aegis depends on every pack being
    // resident for offline emergency operation; the prior "Skip for
    // now" path left users on the home screen with the mic button
    // greyed out and no clear remediation. Better UX: lock them on
    // this screen until the packs finish (it runs in the background,
    // they can lock the device).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            l.downloadAllRequired,
            style: const TextStyle(
              color: AegisColors.onSurfaceMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
        FilledButton(
          onPressed: null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 10),
              Text(l.actionContinue),
            ],
          ),
        ),
      ],
    );
  }
}
