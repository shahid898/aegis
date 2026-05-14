import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
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
/// that has no HuggingFace token wired in. The message is intentionally
/// actionable so a dev sees exactly what to do without digging into source.
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
/// Uses `dio` for byte-accurate progress + cancellation and `package:archive`
/// to decode `.tar.bz2`. One-shot per invocation — no retry/backoff here;
/// the cubit decides policy.
class ModelPackRepository {
  ModelPackRepository(this._dio, this._registry);

  final Dio _dio;
  final ModelRegistry _registry;

  /// Download + install [pack]. Emits progress events; returns when the
  /// pack is extracted and marked installed. Throws on any failure.
  ///
  /// Pass [cancelToken] to cancel mid-download.
  Stream<ModelDownloadProgress> install(
    VoiceModelPack pack, {
    CancelToken? cancelToken,
  }) async* {
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

    final downloadFile = await _downloadTempFile(pack);
    try {
      // ---- Phase 1: download ------------------------------------------------
      final headers = _authHeadersFor(pack);
      final controller = StreamController<ModelDownloadProgress>();
      final downloadFuture = _dio.download(
        pack.archiveUrl,
        downloadFile.path,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: const Duration(minutes: 30),
          responseType: ResponseType.bytes,
          headers: headers,
          // HuggingFace's resolve URL replies with a 302 to a signed S3 URL.
          // Dio follows redirects by default, but the gated check is enforced
          // on the original host, so we keep `followRedirects: true` and let
          // the client reuse our auth header for the first hop only — the
          // signed S3 URL does not need (and rejects) the bearer token.
          followRedirects: true,
        ),
        onReceiveProgress: (received, total) {
          if (controller.isClosed) return;
          controller.add(ModelDownloadProgress(
            pack: pack,
            phase: ModelDownloadPhase.downloading,
            receivedBytes: received,
            totalBytes: total > 0 ? total : pack.approxBytes,
          ));
        },
      ).whenComplete(() => controller.close());

      yield* controller.stream;
      await downloadFuture;

      // ---- Phase 2: verify --------------------------------------------------
      // Defensive: in low-disk situations the staging file can vanish (the
      // OS may evict a too-large temp). Surface a clear error rather than
      // a cryptic PathNotFoundException from File.length().
      if (!await downloadFile.exists()) {
        throw StateError(
          'Downloaded file for ${pack.id} disappeared from staging '
          '(${downloadFile.path}). Likely cause: low disk space or OS cache '
          'eviction. Free up storage and retry.',
        );
      }
      final stagedBytes = await downloadFile.length();
      yield ModelDownloadProgress(
        pack: pack,
        phase: ModelDownloadPhase.verifying,
        receivedBytes: stagedBytes,
        totalBytes: stagedBytes,
      );

      final expected = pack.archiveSha256.trim().toLowerCase();
      if (expected.isNotEmpty) {
        final actual = await _sha256OfFile(downloadFile);
        if (actual != expected) {
          throw ModelIntegrityException(pack.id, expected, actual);
        }
      }

      // ---- Phase 3: install (extract OR copy) ------------------------------
      yield ModelDownloadProgress(
        pack: pack,
        phase: ModelDownloadPhase.extracting,
        receivedBytes: 0,
        totalBytes: 1,
      );

      if (pack.isArchive) {
        await _extractTarBz2(downloadFile, await _registry.root());
      } else {
        await _installDirectFile(pack, downloadFile);
      }

      // Sanity-check: primary model file must exist after install.
      final primaryPath =
          await _registry.absolutePath(pack, pack.modelFile);
      if (!await File(primaryPath).exists()) {
        throw StateError(
          'Install of ${pack.id} did not produce ${pack.modelFile.relativePath}',
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
      if (await downloadFile.exists()) {
        try {
          await downloadFile.delete();
        } on FileSystemException {
          // Best-effort cleanup — a leftover tmp file is survivable.
        }
      }
    }
  }

  /// Temporary download location.
  ///
  /// Staging lives inside the registry root (application-support dir) — NOT
  /// in `getTemporaryDirectory()` — because Android freely evicts the cache
  /// directory under disk pressure, which would silently destroy a long
  /// multi-GB download mid-flight. Same-filesystem staging also keeps the
  /// post-download `rename()` atomic.
  ///
  /// For archive packs the extension is `.tar.bz2`; for direct-file packs
  /// we use `.part` because the actual extension is only meaningful once
  /// the file is moved to its final location.
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
      // rename() fails across filesystems — fall back to a streamed copy.
      await source.copy(targetPath);
    }
  }

  /// Build the HTTP headers needed to download [pack].
  ///
  /// For packs flagged `requiresHfAuth`, this returns an
  /// `Authorization: Bearer <hf-token>` header sourced from the
  /// `HF_TOKEN` compile-time define. If the token is missing we throw
  /// a [MissingHfTokenException] up-front rather than letting Dio
  /// surface an opaque 401 deep inside the install pipeline.
  Map<String, String>? _authHeadersFor(VoiceModelPack pack) {
    if (!pack.requiresHfAuth) return null;
    final token = _hfTokenFromEnv.trim();
    if (token.isEmpty) {
      throw MissingHfTokenException(pack.id, pack.archiveUrl);
    }
    return <String, String>{
      'Authorization': 'Bearer $token',
      // HuggingFace serves the artifact byte-stream — explicitly opt out
      // of the gzipped JSON-error fallback some CDNs return on 4xx.
      'Accept': 'application/octet-stream',
    };
  }

  Future<String> _sha256OfFile(File f) async {
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString();
  }

  /// Extract a `.tar.bz2` into [target]. Preserves the archive's internal
  /// directory structure (sherpa packs ship with a top-level folder that
  /// matches `pack.rootDirName`).
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
