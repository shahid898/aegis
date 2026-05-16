import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../models/accessibility_profile.dart';
import '../../models/app_region.dart';
import '../../models/emergency_contact.dart';
import '../constants/storage_keys.dart';

/// Thin wrapper around Hive boxes. Stores everything as JSON strings so we
/// avoid shipping type adapters through codegen for Phase 1. When the data
/// shape stabilises we can swap individual entries to typed adapters.
class StorageService {
  StorageService._(this._settings, this._contacts);

  final Box<String> _settings;
  final Box<String> _contacts;

  static Future<StorageService> init() async {
    await Hive.initFlutter();
    final settings = await Hive.openBox<String>(StorageBoxes.settings);
    final contacts = await Hive.openBox<String>(StorageBoxes.contacts);
    return StorageService._(settings, contacts);
  }

  // -- Onboarding flag -------------------------------------------------------

  bool get isOnboardingCompleted =>
      _settings.get(StorageKeys.onboardingCompleted) == 'true';

  Future<void> setOnboardingCompleted(bool value) =>
      _settings.put(StorageKeys.onboardingCompleted, value.toString());

  // -- Language -------------------------------------------------------------

  String? get selectedLanguageCode =>
      _settings.get(StorageKeys.selectedLanguageCode);

  Future<void> setSelectedLanguageCode(String code) =>
      _settings.put(StorageKeys.selectedLanguageCode, code);

  /// Notifies on changes to [selectedLanguageCode]. The app shell
  /// wraps `MaterialApp.router` in a `ValueListenableBuilder` against
  /// this so picking a language during onboarding re-renders the
  /// whole tree with the new `Locale` (drives Material/Cupertino
  /// native widget translations + RTL flips without a restart).
  ValueListenable<Box<String>> get languageListenable =>
      _settings.listenable(keys: [StorageKeys.selectedLanguageCode]);

  // -- Region ---------------------------------------------------------------

  AppRegion? get selectedRegion {
    final raw = _settings.get(StorageKeys.selectedRegion);
    if (raw == null) return null;
    return AppRegion.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> setSelectedRegion(AppRegion region) => _settings.put(
        StorageKeys.selectedRegion,
        jsonEncode(region.toJson()),
      );

  // -- Accessibility profile -----------------------------------------------

  AccessibilityProfile get accessibilityProfile {
    final raw = _settings.get(StorageKeys.accessibilityProfile);
    if (raw == null) return const AccessibilityProfile();
    return AccessibilityProfile.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> setAccessibilityProfile(AccessibilityProfile profile) =>
      _settings.put(
        StorageKeys.accessibilityProfile,
        jsonEncode(profile.toJson()),
      );

  // -- Installed voice model packs -----------------------------------------

  List<String> get installedModelIds {
    final raw = _settings.get(StorageKeys.installedModels);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }

  Future<void> setInstalledModelIds(List<String> ids) => _settings.put(
        StorageKeys.installedModels,
        jsonEncode(ids),
      );

  // -- LLM hardware fallback sentinels -------------------------------------
  //
  // Persistent escape hatches for devices where LiteRT-LM's GPU /
  // OpenCL path crashed and corrupted the per-process GL/CL context.
  // Once we observe a recoverable-but-process-fatal crash (e.g.
  // `clEnqueueMapBuffer -14`, `STABLEHLO_COMPOSITE failed to prepare`,
  // `convert_tensor_buffer` reshape error), we persist these flags so
  // the next cold launch starts on the safe path and never re-hits the
  // bug. Both flags are sticky; user-visible reset would live behind a
  // future "Reset hardware" debug setting.

  bool get forceCpuBackend =>
      _settings.get(StorageKeys.llmForceCpuBackend) == 'true';

  Future<void> setForceCpuBackend(bool value) =>
      _settings.put(StorageKeys.llmForceCpuBackend, value.toString());

  bool get disableVision =>
      _settings.get(StorageKeys.llmDisableVision) == 'true';

  Future<void> setDisableVision(bool value) =>
      _settings.put(StorageKeys.llmDisableVision, value.toString());

  // -- Emergency contacts (capped at 5) ------------------------------------

  static const int maxContacts = 5;

  List<EmergencyContact> get emergencyContacts => _contacts.values
      .map((raw) =>
          EmergencyContact.fromJson(jsonDecode(raw) as Map<String, dynamic>))
      .toList(growable: false);

  Future<void> upsertContact(EmergencyContact contact) =>
      _contacts.put(contact.id, jsonEncode(contact.toJson()));

  Future<void> deleteContact(String id) => _contacts.delete(id);

  Future<void> clearContacts() => _contacts.clear();
}
