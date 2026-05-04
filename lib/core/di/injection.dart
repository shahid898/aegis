import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../alert/alert_bridge.dart';
import '../alert/alert_router.dart';
import '../geo/country_resolver.dart';
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

  // Voice services are lazy — engines are heavy and only needed once the
  // user lands on a screen that actually speaks/listens.
  sl.registerLazySingleton<TtsService>(() => TtsService(sl<ModelRegistry>()));
  sl.registerLazySingleton<SttService>(() => SttService(sl<ModelRegistry>()));
  sl.registerLazySingleton<LlmService>(() => LlmService(sl<ModelRegistry>()));

  // Phase 2 wake-app: AlertBridge owns the MethodChannel singleton. We eagerly
  // construct it so the broadcast stream is wired before any UI subscribes,
  // and so cold-start `hydratePending` is a one-line call from the splash.
  sl.registerSingleton<AlertBridge>(AlertBridge());
  sl.registerSingleton<SmsClassifier>(const SmsClassifier());

  // Sprint 2 — FunctionGemma routing. The router lazily reuses the same
  // LlmService that powers the chat loop (flutter_gemma is process-wide
  // singleton) but flips into the router role + uses model.createSession()
  // under the hood so router calls don't pollute the user-facing chat
  // history. The router pack is the small (~270 MB) FunctionGemma 270M
  // checkpoint, distinct from the chat brain (Gemma 4 IT, ~2.5 GB).
  sl.registerLazySingleton<FunctionRouter>(
    () => FunctionRouter(
      llm: sl<LlmService>(),
      routerPack: ModelCatalog.routerPack,
    ),
  );

  // The AlertRouter wires the bridge → classifier → function router →
  // handler dispatch table. We build it eagerly and start it so the very
  // first inbound alert (potentially before any UI is mounted) gets a
  // routing decision instead of just sitting on the broadcast stream.
  final alertRouter = AlertRouter(
    bridge: sl<AlertBridge>(),
    classifier: sl<SmsClassifier>(),
    functionRouter: sl<FunctionRouter>(),
  )..start();
  sl.registerSingleton<AlertRouter>(alertRouter);

  // Warm the FunctionGemma engine so the first real alert isn't paying
  // for shader compile + KV-cache prefill (~25–40 s on cold GPU). We
  // pin the router role (the alert pipeline's pack) and fire the warm-
  // up off the main path — splash / onboarding renders immediately and
  // the engine is hot by the time the user can simulate or receive an
  // alert. If the router pack isn't installed yet (fresh install,
  // download cubit still running) the call is a logged no-op and the
  // first alert just pays the cold-start tax once.
  final llm = sl<LlmService>();
  llm.setRouterPack(ModelCatalog.routerPack);
  llm.useRouter();
  unawaited(
    llm.warmUp().then((_) async {
      if (!kDebugMode) return;
      await llm.runFunctionGemmaMobileActionProbe();
    }),
  );
}
