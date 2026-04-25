import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../geo/country_resolver.dart';
import '../storage/storage_service.dart';
import '../voice/llm_service.dart';
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
}
