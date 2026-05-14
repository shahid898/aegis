import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'app/app.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // flutter_gemma keeps an app-wide service registry; initialise once
  // before any LlmService call. Safe to invoke even when the user never
  // downloads the Gemma pack — no network I/O happens here.
  await FlutterGemma.initialize();
  // FMTC tile cache backend. Opens (or creates) the ObjectBox store on
  // the app documents directory. Required before any FMTCStore /
  // FMTCTileProvider call. Failure here is non-fatal: the inline map
  // falls back to online tiles when the cache backend can't initialise
  // (e.g. ObjectBox native lib missing in tests).
  try {
    await FMTCObjectBoxBackend().initialise();
  } on Object catch (e, st) {
    if (kDebugMode) {
      debugPrint('[main] FMTC init failed (offline map unavailable): $e');
      debugPrintStack(stackTrace: st, label: '[main] FMTC stack');
    }
  }
  await configureDependencies();
  runApp(const AegisApp());
}
