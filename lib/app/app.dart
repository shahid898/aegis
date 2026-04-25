import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'router.dart';
import 'theme.dart';

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Aegis',
      debugShowCheckedModeBanner: false,
      theme: AegisTheme.light(),
      darkTheme: AegisTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
