import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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
  await configureDependencies();
  runApp(const AegisApp());
}
