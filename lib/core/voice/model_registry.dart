import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../storage/storage_service.dart';
import 'model_pack.dart';

/// Tracks which voice model packs are installed on disk and where they
/// live. All packs are extracted under
/// `<application support>/voice_models/<pack.rootDirName>/`.
class ModelRegistry {
  ModelRegistry(this._storage);

  final StorageService _storage;

  Directory? _rootCache;

  /// Root directory that contains every extracted pack. Created on first
  /// access. Uses application-support (not cache) so the OS won't evict.
  Future<Directory> root() async {
    final cached = _rootCache;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/voice_models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _rootCache = dir;
    return dir;
  }

  /// Directory where [pack] is (or will be) extracted.
  Future<Directory> dirFor(VoiceModelPack pack) async {
    final r = await root();
    return Directory('${r.path}/${pack.rootDirName}');
  }

  /// True if the pack id is recorded as installed **and** the primary
  /// model file is present on disk. Protects against half-completed
  /// extractions or manual cache wipes.
  Future<bool> isInstalled(VoiceModelPack pack) async {
    if (!_storage.installedModelIds.contains(pack.id)) return false;
    final dir = await dirFor(pack);
    final primary = File('${dir.path}/${pack.modelFile.relativePath}');
    return primary.exists();
  }

  /// Mark a pack as installed in persistent storage.
  Future<void> markInstalled(VoiceModelPack pack) async {
    final current = _storage.installedModelIds.toSet();
    if (current.add(pack.id)) {
      await _storage.setInstalledModelIds(current.toList(growable: false));
    }
  }

  /// Mark a pack as not installed (used when extraction fails).
  Future<void> markUninstalled(VoiceModelPack pack) async {
    final current = _storage.installedModelIds.toSet();
    if (current.remove(pack.id)) {
      await _storage.setInstalledModelIds(current.toList(growable: false));
    }
  }

  /// Delete the on-disk extraction directory for [pack], then clear the
  /// installed flag. Safe to call even when nothing is on disk.
  Future<void> deletePack(VoiceModelPack pack) async {
    final dir = await dirFor(pack);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await markUninstalled(pack);
  }

  /// Absolute path to a file inside an installed pack.
  Future<String> absolutePath(VoiceModelPack pack, ModelFile file) async {
    final dir = await dirFor(pack);
    return '${dir.path}/${file.relativePath}';
  }

  /// Absolute path to the pack's `dataDir` (espeak-ng data), if any.
  Future<String?> dataDirPath(VoiceModelPack pack) async {
    final name = pack.dataDirName;
    if (name == null) return null;
    final dir = await dirFor(pack);
    return '${dir.path}/$name';
  }
}
