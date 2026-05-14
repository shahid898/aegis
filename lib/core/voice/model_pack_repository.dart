import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';

import 'model_pack.dart';
import 'model_registry.dart';

/// Progress event emitted while a pack downloads/extracts.
class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.pack,
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final VoiceModelPack pack;
  final ModelDownloadPhase phase;
  final int receivedBytes;

  /// -1 when the server did not send Content-Length.
  final int totalBytes;

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

enum ModelDownloadPhase { downloading, verifying, extracting, done }

/// Thrown when the SHA256 of a downloaded archive does not match the
/// catalog-declared digest.
class ModelIntegrityException implements Exception {
  const ModelIntegrityException(this.packId, this.expected, this.actual);
  final String packId;
  final String expected;
  final String actual;

  @override
  String toString() =>
      'ModelIntegrityException($packId): expected $expected, got $actual';
}

/// Thrown when a pack with `requiresHfAuth: true` is installed in a build
/// that has no HuggingFace token wired in.
class MissingHfTokenException implements Exception {
  const MissingHfTokenException(this.packId, this.archiveUrl);
  final String packId;
  final String archiveUrl;

  @override
  String toString() =>
      'MissingHfTokenException($packId): $archiveUrl is hosted in a '
      'gated HuggingFace repo. Accept the license at the model page on '
      'your HuggingFace account, generate a read-only token at '
      'https://huggingface.co/settings/tokens, then rebuild with '
      '`flutter run --dart-define=HF_TOKEN=hf_xxx` (or set HF_TOKEN '
      'before launch). Alternatively, mirror the artifact to an '
      'unauthenticated URL and override it with the matching '
      '`AEGIS_*_URL` define.';
}

/// HuggingFace personal access token, baked in at build time via
/// `--dart-define=HF_TOKEN=hf_xxx`. Empty by default so anonymous
/// downloads continue to work for non-gated packs.
const String _hfTokenFromEnv = "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";

/// Downloads a model pack archive, verifies it, and extracts it on disk.
///
/// Uses `background_downloader` so multi-GB pack downloads survive the
/// app being backgrounded / process kill (Android WorkManager +
/// foreground service, iOS URLSession background queue). Also picks up
/// after flaky-network drops via HTTP Range when the origin supports it.
class ModelPackRepository {
  ModelPackRepository(this._registry) : _downloader = FileDownloader();

  final ModelRegistry _registry;
  final FileDownloader _downloader;

  /// Tracks the in-flight task id per pack so callers can [cancel].
  final Map<String, String> _activeTasks = <String, String>{};

  /// Download + install [pack]. Emits progress events; returns when the
  /// pack is extracted and marked installed. Throws on any failure.
  Stream<ModelDownloadProgress> install(VoiceModelPack pack) async* {
    // Short-circuit if already installed.
    if (await _registry.isInstalled(pack)) {
      yield ModelDownloadProgress(
        pack: pack,
        phase: ModelDownloadPhase.done,
        receivedBytes: pack.approxBytes,
        totalBytes: pack.approxBytes,
      );
      return;
    }

    final stagingFile = await _downloadTempFile(pack);
    final stagingDir = stagingFile.parent.path;
    final stagingFilename = stagingFile.uri.pathSegments.last;
    final headers = _authHeadersFor(pack);

    // Parallel chunked download: 4 concurrent HTTP Range requests
    // against the same origin. HuggingFace's resolve URL redirects to
    // S3 which honors Range — typical wall-clock gain is 2-4× over a
    // single-stream Dio download. Trade-off: ParallelDownloadTask
    // cannot pause/resume on failure (the chunk plan is in-memory only
    // and cancellation cascades to every chunk). Retries still work —
    // the whole task retries from scratch up to `retries` times — so
    // transient drops auto-recover, just from byte 0 of the failed
    // chunk's range, not the file. Cancel still works the same way.
    final task = ParallelDownloadTask(
      taskId: 'aegis-pack-${pack.id}',
      url: pack.archiveUrl,
      filename: stagingFilename,
      chunks: 4,
      // Absolute path. We resolve `${registryRoot}/.staging/` via
      // baseDirectory.root and a literal directory string so the
      // plugin can find the same staging file across launches without
      // recomputing app-support paths (which can differ between cold
      // and warm starts on some Android skins).
      baseDirectory: BaseDirectory.root,
      directory: stagingDir,
      headers: headers ?? const <String, String>{},
      retries: 5,
      updates: Updates.statusAndProgress,
      // Surface to the OS so a backgrounded download keeps a system
      // notification visible (Android requires this for long-running
      // foreground services).
      displayName: 'Aegis model · ${pack.id}',
    );

    _activeTasks[pack.id] = task.taskId;
    final controller = StreamController<ModelDownloadProgress>();

    void emitProgress(double fraction) {
      if (controller.isClosed) return;
      // background_downloader's `onProgress` reports 0.0..1.0. We
      // scale by the catalog's expected byte count so the UI can show
      // "523 / 1842 MB" without depending on Content-Length.
      final total = pack.approxBytes;
      final received = (fraction.clamp(0.0, 1.0) * total).round();
      controller.add(ModelDownloadProgress(
        pack: pack,
        phase: ModelDownloadPhase.downloading,
        receivedBytes: received,
        totalBytes: total,
      ));
    }

    late final Future<TaskStatusUpdate> downloadFuture;
    try {
      downloadFuture = _downloader
          .download(task, onProgress: emitProgress)
          .whenComplete(() => controller.close());

      yield* controller.stream;

      final result = await downloadFuture;
      if (result.status == TaskStatus.canceled) {
        // Cubit-initiated cancel — bubble up as a typed exception so
        // upstream can distinguish "user canceled" from "network died".
        throw _DownloadCanceledException(pack.id);
      }
      if (result.status != TaskStatus.complete) {
        final reason = result.exception?.description ?? 'unknown';
        throw StateError(
          'Download failed for ${pack.id}: ${result.status} ($reason)',
        );
      }

      // ---- Phase 2: verify ----------------------------------------------
      if (!await stagingFile.exists()) {
        throw StateError(
          'Downloaded file for ${pack.id} disappeared from staging '
          '(${stagingFile.path}). Likely cause: low disk space or OS cache '
          'eviction. Free up storage and retry.',
        );
      }
      final stagedBytes = await stagingFile.length();
      yield ModelDownloadProgress(
        pack: pack,
        phase: ModelDownloadPhase.verifying,
        receivedBytes: stagedBytes,
        totalBytes: stagedBytes,
      );

      final expected = pack.archiveSha256.trim().toLowerCase();
      if (expected.isNotEmpty) {
        final actual = await _sha256OfFile(stagingFile);
        if (actual != expected) {
          throw ModelIntegrityException(pack.id, expected, actual);
        }
      }

      // ---- Phase 3: install ---------------------------------------------
      yield ModelDownloadProgress(
        pack: pack,
        phase: ModelDownloadPhase.extracting,
        receivedBytes: 0,
        totalBytes: 1,
      );

      if (pack.isArchive) {
        await _extractTarBz2(stagingFile, await _registry.root());
      } else {
        await _installDirectFile(pack, stagingFile);
      }

      final primaryPath =
          await _registry.absolutePath(pack, pack.modelFile);
      if (!await File(primaryPath).exists()) {
        throw StateError(
          'Install of ${pack.id} did not produce '
          '${pack.modelFile.relativePath}',
        );
      }

      await _registry.markInstalled(pack);

      yield ModelDownloadProgress(
        pack: pack,
        phase: ModelDownloadPhase.done,
        receivedBytes: 1,
        totalBytes: 1,
      );
    } finally {
      _activeTasks.remove(pack.id);
      if (await stagingFile.exists()) {
        try {
          await stagingFile.delete();
        } on FileSystemException {
          // Best-effort cleanup — a leftover tmp file is survivable.
        }
      }
    }
  }

  /// Cancel an in-flight pack download. No-op when nothing is running
  /// for [pack]. Resolves to true when the native side accepted the
  /// cancel.
  Future<bool> cancel(VoiceModelPack pack) async {
    final taskId = _activeTasks[pack.id];
    if (taskId == null) return false;
    return _downloader.cancelTaskWithId(taskId);
  }

  // NB: pause/resume removed. We use [ParallelDownloadTask] for the
  // 2-4× speed-up, and the plugin doesn't support pause on parallel
  // downloads (the chunk plan is in-memory only). Cancel + retry are
  // the only flow-control levers. If pause/resume becomes a hard
  // product requirement later, switch back to plain [DownloadTask]
  // with `allowPause: true` and eat the single-stream throughput.

  /// Temporary download location, kept inside the registry root so the
  /// post-download `rename()` stays atomic on the same filesystem.
  Future<File> _downloadTempFile(VoiceModelPack pack) async {
    final root = await _registry.root();
    final dir = Directory('${root.path}/.staging');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final suffix = pack.isArchive ? 'tar.bz2' : 'part';
    return File('${dir.path}/${pack.id}.$suffix');
  }

  /// Copy a direct-file download (e.g. a flutter_gemma `.task` bundle)
  /// into its final location under the registry root.
  Future<void> _installDirectFile(VoiceModelPack pack, File source) async {
    final targetDir = await _registry.dirFor(pack);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final targetPath =
        await _registry.absolutePath(pack, pack.modelFile);
    final targetFile = File(targetPath);
    final parent = targetFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    try {
      await source.rename(targetPath);
    } on FileSystemException {
      await source.copy(targetPath);
    }
  }

  /// Build the HTTP headers needed to download [pack].
  Map<String, String>? _authHeadersFor(VoiceModelPack pack) {
    if (!pack.requiresHfAuth) return null;
    final token = _hfTokenFromEnv.trim();
    if (token.isEmpty) {
      throw MissingHfTokenException(pack.id, pack.archiveUrl);
    }
    return <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/octet-stream',
    };
  }

  Future<String> _sha256OfFile(File f) async {
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString();
  }

  Future<void> _extractTarBz2(File archiveFile, Directory target) async {
    final compressed = await archiveFile.readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(compressed);
    final archive = TarDecoder().decodeBytes(tarBytes);

    for (final entry in archive) {
      final outPath = '${target.path}/${entry.name}';
      if (entry.isFile) {
        final data = entry.content as List<int>;
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(data);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }
}

/// Thrown internally when the user-initiated cancel races with the
/// completed signal from the native side. Exposed so the cubit can
/// classify the failure as "canceled" rather than "errored".
class _DownloadCanceledException implements Exception {
  const _DownloadCanceledException(this.packId);
  final String packId;
  @override
  String toString() => 'Download canceled for $packId';
}
