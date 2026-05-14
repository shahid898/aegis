import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../../features/reports/data/reports_repository.dart';
import '../alert/alert_briefing_sink.dart';
import '../alert/alert_bridge.dart';
import '../alert/alert_router.dart';
import '../geo/country_resolver.dart';
import '../places/places_repository.dart';
import '../skills/skills_registry.dart';
import '../llm/function_router.dart';
import '../sms_classifier/sms_classifier.dart';
import '../storage/storage_service.dart';
import '../voice/llm_service.dart';
import '../voice/model_catalog.dart';
import '../voice/model_pack_repository.dart';
import '../voice/model_registry.dart';
import '../voice/stt_service.dart';
import '../voice/tts_service.dart';

final GetIt sl = GetIt.instance;

Future<void> configureDependencies() async {
  final storage = await StorageService.init();
  sl.registerSingleton<StorageService>(storage);

  sl.registerSingleton<Dio>(
    Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 30),
    )),
  );

  sl.registerSingleton<CountryResolver>(const CountryResolver());

  sl.registerSingleton<ModelRegistry>(ModelRegistry(sl<StorageService>()));
  sl.registerSingleton<ModelPackRepository>(
    ModelPackRepository(sl<Dio>(), sl<ModelRegistry>()),
  );

  // Agent Skills catalog. Singleton: the catalog is read-only after
  // load and shared across LlmService and any future surfaces (eg. a
  // "browse skills" debug screen). Loaded on first access via
  // SkillsRegistry.load() inside LlmService.triageStream.
  sl.registerSingleton<SkillsRegistry>(SkillsRegistry());

  // Offline POI cache for find-nearby-places. Lazy: opens places.db on
  // first read so apps that never invoke the skill don't pay sqflite
  // init cost. Seeded once during onboarding by
  // [OnboardingPlacesDownloader].
  sl.registerSingleton<PlacesRepository>(PlacesRepository());

  // Reports archive — confirmed triage cards land here. Opens its own
  // Hive box at startup so the Reports page can read a fresh snapshot
  // without an async wait.
  sl.registerSingleton<ReportsRepository>(await ReportsRepository.open());

  // Voice services are lazy — engines are heavy and only needed once the
  // user lands on a screen that actually speaks/listens.
  sl.registerLazySingleton<TtsService>(() => TtsService(sl<ModelRegistry>()));
  sl.registerLazySingleton<LlmService>(
    () => LlmService(
      sl<ModelRegistry>(),
      skills: sl<SkillsRegistry>(),
      // Persist hardware-fallback sentinels through Hive so a single
      // GPU / vision crash on this device sticks across cold launches.
      // Wrapper is hand-rolled (no codegen) so LlmService stays
      // independent of the Hive layer in tests.
      hardwareStore: _StorageHardwareFallbackStore(sl<StorageService>()),
    ),
  );
  // SttService uses Gemma 4 for transcription via a callback into LlmService
  // so it never holds a direct reference to LlmService itself.
  sl.registerLazySingleton<SttService>(
    () => SttService(
      sl<ModelRegistry>(),
      (wavBytes) => sl<LlmService>().transcribeAudio(wavBytes),
    ),
  );
  // Phase 2 wake-app: AlertBridge owns the MethodChannel singleton. We eagerly
  // construct it so the broadcast stream is wired before any UI subscribes,
  // and so cold-start `hydratePending` is a one-line call from the splash.
  sl.registerSingleton<AlertBridge>(AlertBridge());
  sl.registerSingleton<SmsClassifier>(const SmsClassifier());

  // Pub/sub seam between SummarizeForUserHandler (publisher) and the
  // in-app assistant surface (subscriber). Held as a singleton so any
  // surface — assistant cubit, takeover screen — can subscribe without
  // touching the alert handler internals.
  sl.registerSingleton<AlertBriefingSink>(AlertBriefingSink());

  // Sprint 2 — Gemma 4 IT routing. We retired the FunctionGemma 270M router
  // pack: it's a general agentic tool-calling fine-tune that knows nothing
  // about disaster terminology and on-device escalated both real cyclone
  // alerts and promo/test SMS. Gemma 4 IT (the chat brain) classifies
  // disaster intent zero-shot via a strict VERDICT/SEVERITY/REASON envelope
  // — see [FunctionRouter] for the protocol. Same engine as the chat loop;
  // [LlmService.oneShot] runs in a fresh history-free session so routing
  // never pollutes the user-facing conversation.
  sl.registerLazySingleton<FunctionRouter>(
        () => FunctionRouter(llm: sl<LlmService>(), chatPack: ModelCatalog.llmPack),
  );

  // The AlertRouter wires the bridge → classifier → function router →
  // handler dispatch table. We build it eagerly and start it so the very
  // first inbound alert (potentially before any UI is mounted) gets a
  // routing decision instead of just sitting on the broadcast stream.
  final alertRouter = AlertRouter(
    bridge: sl<AlertBridge>(),
    classifier: sl<SmsClassifier>(),
    functionRouter: sl<FunctionRouter>(),
    tts: sl<TtsService>(),
    storage: sl<StorageService>(),
    briefingSink: sl<AlertBriefingSink>(),
    // Pull the user's onboarding-selected language fresh on every
    // alert so language changes take effect without restarting the
    // router. Returns null when onboarding hasn't completed — the
    // FunctionRouter falls back to "alert's own language" in that
    // case.
    preferredLanguage: () => sl<StorageService>().selectedLanguageCode,
  )..start();
  sl.registerSingleton<AlertRouter>(alertRouter);

  // Warm the Gemma 4 IT engine so the first real alert (and the first
  // chat turn) isn't paying for shader compile + KV-cache prefill on a
  // cold GPU. Gemma 4 IT is now the routing brain too, so a single warm-
  // up covers both paths. If the chat pack isn't installed yet (fresh
  // install, download cubit still running) the call is a logged no-op
  // and the first alert just pays the cold-start tax once.
  final llm = sl<LlmService>();
  llm.setChatPack(ModelCatalog.llmPack);
  llm.useChat();
  unawaited(llm.warmUp());
}

/// Thin Hive-backed adapter for [LlmService]'s hardware-fallback
/// sentinels. Keeps `LlmService` free of a direct `StorageService`
/// dependency — tests can pass an in-memory fake or omit the store
/// entirely (LlmService falls back to in-process-only behavior).
class _StorageHardwareFallbackStore implements HardwareFallbackStore {
  _StorageHardwareFallbackStore(this._storage);

  final StorageService _storage;

  @override
  bool readForceCpu() => _storage.forceCpuBackend;

  @override
  bool readDisableVision() => _storage.disableVision;

  @override
  Future<void> persistForceCpu() => _storage.setForceCpuBackend(true);

  @override
  Future<void> persistDisableVision() => _storage.setDisableVision(true);
}
