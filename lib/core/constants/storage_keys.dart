class StorageBoxes {
  const StorageBoxes._();

  static const String settings = 'settings_box';
  static const String contacts = 'contacts_box';
  static const String reports = 'reports_box';
}

class StorageKeys {
  const StorageKeys._();

  static const String onboardingCompleted = 'onboarding_completed';
  static const String selectedLanguageCode = 'selected_language_code';
  static const String selectedRegion = 'selected_region';
  static const String accessibilityProfile = 'accessibility_profile';
  static const String installedModels = 'installed_models';

  /// Persisted GPU-failure sentinels. Set the first time LiteRT-LM's
  /// OpenCL/Mali path crashed (clEnqueueMapBuffer, STABLEHLO_COMPOSITE,
  /// tensor-buffer reshape). Once set, the next cold launch boots the
  /// LLM directly on the CPU backend so the user never re-hits the
  /// same in-process GPU corruption. Manual reset only.
  static const String llmForceCpuBackend = 'llm_force_cpu_backend';

  /// Persisted vision-decode failure sentinel. Set when vision decode
  /// crashed even after the CPU fallback. Future triages on this
  /// device skip the image attachment so the report still lands from
  /// audio / text / GPS evidence.
  static const String llmDisableVision = 'llm_disable_vision';
}
