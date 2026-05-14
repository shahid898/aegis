import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/places/onboarding_places_downloader.dart';
import '../../../../core/places/tile_cache_downloader.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/voice/model_pack.dart';
import '../../../../core/voice/model_pack_repository.dart';
import '../../../../core/voice/model_registry.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Prepare offline voice')),
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
                    'Downloading voice models',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aegis works fully offline after this one-time '
                    'download. You can skip and run in text-only mode.',
                    style: TextStyle(
                      color: AegisColors.onSurfaceMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _OverallProgress(state: state),
                  if (state.placesProgressMessage.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (state.status == DownloadStatus.seedingPlaces) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ] else ...[
                          const Icon(Icons.check_circle_outline,
                              size: 16, color: AegisColors.primary),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            state.placesProgressMessage,
                            style: const TextStyle(
                              color: AegisColors.onSurfaceMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (state.tilesProgressMessage.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (state.status == DownloadStatus.seedingTiles) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ] else ...[
                          const Icon(Icons.check_circle_outline,
                              size: 16, color: AegisColors.primary),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            state.tilesProgressMessage,
                            style: const TextStyle(
                              color: AegisColors.onSurfaceMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.separated(
                      itemCount: state.plan.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _PackTile(
                        pack: state.plan[i],
                        state: state,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: state.overallFraction == 0 ? null : state.overallFraction,
          minHeight: 10,
          borderRadius: BorderRadius.circular(5),
        ),
        const SizedBox(height: 8),
        Text(
          '${(state.overallFraction * 100).toStringAsFixed(0)}% complete',
          style: const TextStyle(color: AegisColors.onSurfaceMuted),
        ),
      ],
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({required this.pack, required this.state});

  final VoiceModelPack pack;
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    final installed = state.installedIds.contains(pack.id);
    final isCurrent = state.currentPack?.id == pack.id && !installed;
    final sizeMb = (pack.approxBytes / (1024 * 1024)).toStringAsFixed(0);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _StatusIcon(installed: installed, current: isCurrent, state: state),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    installed
                        ? 'Installed'
                        : isCurrent
                            ? _currentSubtitle(state, sizeMb)
                            : '$sizeMb MB • pending',
                    style: const TextStyle(
                      color: AegisColors.onSurfaceMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _currentSubtitle(ModelDownloadState state, String sizeMb) {
    return switch (state.status) {
      DownloadStatus.downloading =>
        '${(state.currentReceivedBytes / (1024 * 1024)).toStringAsFixed(1)} '
            '/ $sizeMb MB',
      DownloadStatus.verifying => 'Verifying…',
      DownloadStatus.extracting => 'Extracting…',
      _ => '$sizeMb MB',
    };
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.installed,
    required this.current,
    required this.state,
  });

  final bool installed;
  final bool current;
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    if (installed) {
      return const Icon(Icons.check_circle, color: AegisColors.primary);
    }
    if (current && state.status == DownloadStatus.downloading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }
    return const Icon(Icons.radio_button_unchecked,
        color: AegisColors.onSurfaceMuted);
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.state});
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    if (state.status == DownloadStatus.failed) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AegisColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              state.errorMessage ?? 'Download failed.',
              style: const TextStyle(color: AegisColors.danger),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.go(AppRoute.accessibility.path),
                  child: const Text('Skip for now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.read<ModelDownloadCubit>().start(),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (state.allInstalled || state.status == DownloadStatus.completed) {
      return FilledButton(
        onPressed: () => context.go(AppRoute.accessibility.path),
        child: const Text('Continue'),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              context.read<ModelDownloadCubit>().skip();
              context.go(AppRoute.accessibility.path);
            },
            child: const Text('Skip for now'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: state.status == DownloadStatus.downloading
                ? () => context.read<ModelDownloadCubit>().cancel()
                : () => context.read<ModelDownloadCubit>().start(),
            child: Text(
              state.status == DownloadStatus.downloading
                  ? 'Cancel'
                  : 'Resume',
            ),
          ),
        ),
      ],
    );
  }
}
