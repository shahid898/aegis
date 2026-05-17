import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
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
const String _hfTokenFromEnv = String.fromEnvironment('HF_TOKEN');

/// Downloads a model pack archive, verifies it, and extracts it on disk.
///
/// Uses `background_downloader` so multi-GB pack downloads survive the
/// app being backgrounded / process kill (Android WorkManager +
/// foreground service, iOS URLSession background queue). Also picks up
/// after flaky-network drops via HTTP Range when the origin supports it.
///
/// Single-stream `DownloadTask` (not `ParallelDownloadTask`): HF's CDN
/// (`cdn-lfs.huggingface.co`) saturates one TCP pipe better than four
/// chunked Range requests, especially on mobile networks where extra
/// connections inflate packet loss and trigger 429 retry storms. The
/// previous 4-chunk parallel task wall-clocked at 10-15 min for the
/// 2.5 GB Gemma artifact; single-stream hits 2-4 min on the same link.
class ModelPackRepository {
  ModelPackRepository(this._registry) : _downloader = FileDownloader();

  final ModelRegistry _registry;
  final FileDownloader _downloader;

  /// Tracks the in-flight task id per pack so callers can [cancel].
  final Map<String, String> _activeTasks = <String, String>{};

  /// Download + install [pack]. Emits progress events; returns when the
  /// pack is extracted and marked installed. Throws on any failure.
  Stream<ModelDownloadProgress> install(VoiceModelPack pack) async* {
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

    // Single-stream download. HuggingFace + Cloudfront serve one TCP
    // connection at near-line-rate; parallel chunks against the same
    // origin hurt more than they help on mobile networks. Pause/resume
    // works (the plugin records partial bytes and sends a `Range:` on
    // retry), so transient drops don't restart the whole file.
    final task = DownloadTask(
      taskId: 'aegis-pack-${pack.id}',
      url: pack.archiveUrl,
      filename: stagingFilename,
      baseDirectory: BaseDirectory.root,
      directory: stagingDir,
      headers: headers ?? const <String, String>{},
      retries: 5,
      allowPause: true,
      updates: Updates.statusAndProgress,
      displayName: 'Aegis model · ${pack.id}',
    );

    _activeTasks[pack.id] = task.taskId;
    final controller = StreamController<ModelDownloadProgress>();

    void emitProgress(double fraction) {
      if (controller.isClosed) return;
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
        throw _DownloadCanceledException(pack.id);
      }
      if (result.status != TaskStatus.complete) {
        final reason = result.exception?.description ?? 'unknown';
        throw StateError(
          'Download failed for ${pack.id}: ${result.status} ($reason)',
        );
      }

      if (!await stagingFile.exists()) {
        throw StateError(
          'Downloaded file for ${pack.id} disappeared from staging '
          '(${stagingFile.path}). Likely cause: low disk space or OS cache '
          'eviction. Free up storage and retry.',
        );
      }

      // ---- Phase 2: verify ----------------------------------------------
      final expected = pack.archiveSha256.trim().toLowerCase();
      if (expected.isNotEmpty) {
        final stagedBytes = await stagingFile.length();
        yield ModelDownloadProgress(
          pack: pack,
          phase: ModelDownloadPhase.verifying,
          receivedBytes: stagedBytes,
          totalBytes: stagedBytes,
        );
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
        final targetRoot = await _registry.root();
        // Off-load bz2+tar decode to a background isolate so the UI
        // stays smooth on a 1-2 GB extract. Streaming I/O via
        // InputFileStream/OutputFileStream keeps peak RAM at one
        // OutputFileStream buffer (~64 KB) instead of the whole tar.
        //
        // The call goes through `_runExtractInIsolate` (static) instead
        // of `Isolate.run(() => ...)` inline because Dart copies the
        // closure's *entire* enclosing lexical scope, not just the
        // names it references. `install()` has a StreamController and a
        // Future in scope; both are unsendable and cause
        //   Invalid argument(s): Illegal argument in isolate message:
        //   object is unsendable - Library:'dart:async' Class: _Future
        // when serializing the closure. Routing through a static method
        // shrinks the captured context to two `String`s, both sendable.
        await _runExtractInIsolate(stagingFile.path, targetRoot.path);
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

  /// Static helper that wraps [Isolate.run] so its closure captures
  /// only the two `String` arguments below — not the entire lexical
  /// scope of [install], which contains a StreamController + Future
  /// that are unsendable across isolates. See call site for the full
  /// rationale.
  static Future<void> _runExtractInIsolate(
    String archivePath,
    String targetPath,
  ) =>
      Isolate.run(() => _extractTarBz2Streaming(archivePath, targetPath));
}

/// Streaming tar.bz2 extractor. Runs inside [Isolate.run] so the
/// UI isolate stays interactive while a multi-GB archive decompresses
/// on slow ARM cores. Top-level (not a class method) because
/// `Isolate.run` requires a sendable closure.
///
/// Implementation notes:
///  - bz2 is decompressed *to a temp .tar file* with [BZip2Decoder.decodeStream]
///    so we never hold the decompressed tar bytes in RAM. The previous
///    `BZip2Decoder().decodeBytes(await file.readAsBytes())` path
///    allocated the entire compressed bz2 AND the decompressed tar in
///    RAM simultaneously — easily 1+ GB on a phone, which is the
///    other half of the "10-15 min" slowness (OOM kills + swap thrash).
///  - tar is then decoded via [TarDecoder.decodeStream] (lazy, file-
///    backed) and entries are written one at a time with
///    [OutputFileStream], same pattern as `extractArchiveToDisk`.
Future<void> _extractTarBz2Streaming(
  String archivePath,
  String targetPath,
) async {
  final tarPath = '$archivePath.tar';

  final bzIn = InputFileStream(archivePath);
  final tarOut = OutputFileStream(tarPath);
  try {
    BZip2Decoder().decodeStream(bzIn, tarOut);
  } finally {
    await bzIn.close();
    await tarOut.close();
  }

  final tarIn = InputFileStream(tarPath);
  try {
    final archive = TarDecoder().decodeStream(tarIn);
    for (final entry in archive) {
      final outPath = '$targetPath/${entry.name}';
      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        final out = OutputFileStream(outPath);
        try {
          entry.writeContent(out);
        } finally {
          await out.close();
        }
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  } finally {
    await tarIn.close();
    try {
      await File(tarPath).delete();
    } on FileSystemException {
      // Best-effort cleanup.
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
