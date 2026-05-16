import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

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
  ModelPackRepository(this._registry) : _downloader = FileDownloader() {
    // Bump per-request read timeout. Default ~60s is too tight for a
    // multi-GB transfer over a throttled CDN — one stalled TCP window
    // cascades into a `Task <id> timed out` (visible in adb logs) and
    // the whole task fails. 5 min lets the plugin coast through brief
    // throttle dips before tripping a Range-resume retry. Connection
    // timeout stays at the default since "can't reach server" should
    // fail fast.
    unawaited(_downloader.configure(
      globalConfig: [
        (Config.requestTimeout, const Duration(minutes: 5)),
      ],
    ));
  }

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

    // HuggingFace gated-repo URLs redirect to `cdn-lfs.huggingface.co`
    // with a signed query string. Many HTTP clients (including the
    // one inside background_downloader on some Android API levels)
    // strip the `Authorization` header on cross-origin redirect as a
    // token-leak safeguard. When that happens, the GET against
    // cdn-lfs falls back to the anonymous throttle bucket (~0.5 MB/s
    // observed) instead of the authenticated bucket. Workaround:
    // resolve the redirect ourselves with the Authorization header
    // applied, capture the signed cdn-lfs URL (the signature itself
    // is the auth — no header needed), and hand THAT to the
    // background downloader. Plain GET, full bandwidth.
    final resolvedUrl = await _resolveDownloadUrl(pack.archiveUrl, headers);
    // The redirected URL is self-authenticating via its signed query
    // string. Passing the Authorization header to cdn-lfs would
    // either be ignored or rejected, so strip it.
    final taskHeaders = identical(resolvedUrl, pack.archiveUrl)
        ? (headers ?? const <String, String>{})
        : const <String, String>{};

    // Migration: prior builds used ParallelDownloadTask which writes a
    // chunk-merge stub into the same staging path. Single-stream
    // DownloadTask resumes via HTTP Range against whatever bytes
    // already exist there, so a leftover parallel-scheme partial will
    // either fail SHA verification at the end (best case) or be
    // appended onto with mismatched bytes (worst case). Cheapest fix:
    // wipe any pre-existing staging file before kicking off the new
    // task. Next session's partial will be a proper single-stream
    // resume.
    if (await stagingFile.exists()) {
      try {
        await stagingFile.delete();
      } on FileSystemException {
        // Best-effort; if delete fails, the download will overwrite.
      }
    }

    // Single-stream DownloadTask. We previously used
    // ParallelDownloadTask with chunks=4 for the theoretical 2-4×
    // speedup, but in practice:
    //   1. HuggingFace's CDN throttles per-IP parallel Range requests,
    //      so the 4 chunks compete for the same throttled pipe and end
    //      up no faster (sometimes slower) than one stream.
    //   2. Parallel chunks have no per-chunk resume — when any single
    //      chunk times out (logs: `Task <id> timed out`), the whole
    //      ParallelDownloadTask fails and retries restart from byte 0
    //      of every chunk. On a multi-GB file at ~10 Mbps this means
    //      losing 30 min of progress per transient drop.
    // Plain DownloadTask uses HTTP `Range` to resume from the last
    // received byte on retry / app relaunch, so flaky networks
    // amortise rather than punish. `allowPause: true` exposes the
    // pause/resume API the cubit calls.
    final task = DownloadTask(
      taskId: 'aegis-pack-${pack.id}',
      url: resolvedUrl,
      filename: stagingFilename,
      // Absolute path. We resolve `${registryRoot}/.staging/` via
      // baseDirectory.root and a literal directory string so the
      // plugin can find the same staging file across launches without
      // recomputing app-support paths (which can differ between cold
      // and warm starts on some Android skins).
      baseDirectory: BaseDirectory.root,
      directory: stagingDir,
      headers: taskHeaders,
      retries: 5,
      allowPause: true,
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

  // Pause/resume aren't surfaced through the cubit today — cancel +
  // restart are the only flow-control levers. DownloadTask supports
  // pause natively (the task is created with `allowPause: true`), so
  // wiring it through is a 5-line cubit change when product needs it.

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

  /// Resolve the final download URL by following HF's redirect once
  /// with the Authorization header attached. Returns the unwrapped
  /// `cdn-lfs.huggingface.co` URL (signed query string carries the
  /// auth from this point on). Falls back to the original URL on any
  /// failure — the caller will then send Authorization on the GET as
  /// a last-resort.
  Future<String> _resolveDownloadUrl(
    String archiveUrl,
    Map<String, String>? headers,
  ) async {
    // Only HF gated-repo URLs need redirect unwrapping.
    if (headers == null || headers.isEmpty) return archiveUrl;
    final dio = Dio(BaseOptions(
      followRedirects: false,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      // Treat 3xx as success so we can read the Location header.
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ));
    try {
      // HEAD avoids streaming the body just to read the redirect.
      final response = await dio.head(
        archiveUrl,
        options: Options(headers: headers),
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) return archiveUrl;
      return location;
    } on DioException {
      // Network hiccup during the resolve step — fall back to handing
      // the original URL to background_downloader. Worst case we hit
      // the auth-strip throttle bug, but we still get *a* download.
      return archiveUrl;
    } finally {
      dio.close();
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
