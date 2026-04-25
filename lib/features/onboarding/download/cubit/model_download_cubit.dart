import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/voice/model_catalog.dart';
import '../../../../core/voice/model_pack.dart';
import '../../../../core/voice/model_pack_repository.dart';
import '../../../../core/voice/model_registry.dart';

part 'model_download_cubit.freezed.dart';

enum DownloadStatus {
  idle,
  downloading,
  verifying,
  extracting,
  completed,
  failed,
  cancelled,
}

@freezed
abstract class ModelDownloadState with _$ModelDownloadState {
  const factory ModelDownloadState({
    required List<VoiceModelPack> plan,
    @Default(<String>{}) Set<String> installedIds,
    @Default(DownloadStatus.idle) DownloadStatus status,
    VoiceModelPack? currentPack,
    @Default(0) int currentReceivedBytes,
    @Default(1) int currentTotalBytes,
    String? errorMessage,
  }) = _ModelDownloadState;

  const ModelDownloadState._();

  factory ModelDownloadState.forPlan(
    List<VoiceModelPack> plan,
    Set<String> installedIds,
  ) =>
      ModelDownloadState(plan: plan, installedIds: installedIds);

  /// Fraction of the *whole plan* completed, not just the current pack.
  double get overallFraction {
    if (plan.isEmpty) return 1;
    final totalPacks = plan.length;
    final completedPacks =
        plan.where((p) => installedIds.contains(p.id)).length;
    final current = currentPack;
    double currentFrac = 0;
    if (current != null &&
        !installedIds.contains(current.id) &&
        currentTotalBytes > 0) {
      currentFrac =
          (currentReceivedBytes / currentTotalBytes).clamp(0.0, 1.0);
    }
    return ((completedPacks + currentFrac) / totalPacks).clamp(0.0, 1.0);
  }

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.cancelled ||
      status == DownloadStatus.failed;

  bool get allInstalled => plan.every((p) => installedIds.contains(p.id));
}

class ModelDownloadCubit extends Cubit<ModelDownloadState> {
  ModelDownloadCubit({
    required this.countryCode,
    required ModelPackRepository repository,
    required ModelRegistry registry,
  })  : _repository = repository,
        _registry = registry,
        super(ModelDownloadState.forPlan(
          ModelCatalog.planFor(countryCode).all,
          const <String>{},
        )) {
    _bootstrap();
  }

  final String countryCode;
  final ModelPackRepository _repository;
  final ModelRegistry _registry;

  CancelToken? _cancelToken;
  StreamSubscription<ModelDownloadProgress>? _sub;

  Future<void> _bootstrap() async {
    final installed = <String>{};
    for (final pack in state.plan) {
      if (await _registry.isInstalled(pack)) installed.add(pack.id);
    }
    emit(state.copyWith(installedIds: installed));
  }

  /// Download every pack in [state.plan] that is not yet installed,
  /// in order. TTS packs first so the language picker has voice ASAP.
  Future<void> start() async {
    if (state.status == DownloadStatus.downloading) return;
    emit(state.copyWith(
      status: DownloadStatus.downloading,
      errorMessage: null,
    ));

    for (final pack in state.plan) {
      if (state.installedIds.contains(pack.id)) continue;
      if (state.status == DownloadStatus.cancelled) return;

      _cancelToken = CancelToken();
      try {
        await _runOne(pack);
      } on Object catch (e) {
        if (_cancelToken?.isCancelled ?? false) {
          emit(state.copyWith(status: DownloadStatus.cancelled));
          return;
        }
        emit(state.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        ));
        return;
      }
    }

    emit(state.copyWith(
      status: DownloadStatus.completed,
      currentPack: null,
    ));
  }

  Future<void> _runOne(VoiceModelPack pack) async {
    emit(state.copyWith(
      currentPack: pack,
      currentReceivedBytes: 0,
      currentTotalBytes: pack.approxBytes,
      status: DownloadStatus.downloading,
    ));

    await _sub?.cancel();
    final completer = Completer<void>();
    _sub = _repository
        .install(pack, cancelToken: _cancelToken)
        .listen(
      (p) {
        emit(state.copyWith(
          status: switch (p.phase) {
            ModelDownloadPhase.downloading => DownloadStatus.downloading,
            ModelDownloadPhase.verifying => DownloadStatus.verifying,
            ModelDownloadPhase.extracting => DownloadStatus.extracting,
            ModelDownloadPhase.done => DownloadStatus.downloading,
          },
          currentReceivedBytes: p.receivedBytes,
          currentTotalBytes: p.totalBytes > 0 ? p.totalBytes : pack.approxBytes,
        ));
      },
      onError: completer.completeError,
      onDone: () {
        emit(state.copyWith(
          installedIds: {...state.installedIds, pack.id},
        ));
        completer.complete();
      },
      cancelOnError: true,
    );
    await completer.future;
  }

  /// Abort the current download. Packs already extracted stay installed.
  Future<void> cancel() async {
    _cancelToken?.cancel('user cancelled');
    await _sub?.cancel();
    _sub = null;
    emit(state.copyWith(status: DownloadStatus.cancelled));
  }

  /// Skip downloads entirely. App will run in degraded mode (no voice).
  /// Caller navigates away — this just marks the state so the UI can show
  /// a clear "skipped" message if the user comes back.
  void skip() {
    _cancelToken?.cancel('user skipped');
    emit(state.copyWith(status: DownloadStatus.cancelled));
  }

  @override
  Future<void> close() async {
    _cancelToken?.cancel('cubit closed');
    await _sub?.cancel();
    return super.close();
  }
}
