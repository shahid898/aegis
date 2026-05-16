import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/constants/languages.dart';
import '../core/di/injection.dart';
import '../core/storage/storage_service.dart';
import '../l10n/generated/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = sl<StorageService>();
    // Rebuild MaterialApp.router whenever the persisted language code
    // changes so the app's `Locale` flips live during onboarding —
    // picks up RTL direction + Material/Cupertino native widget
    // translations without an app restart.
    return ListenableBuilder(
      listenable: storage.languageListenable,
      builder: (context, _) {
        final code = storage.selectedLanguageCode;
        final locale = (code != null && code.isNotEmpty) ? Locale(code) : null;
        return MaterialApp.router(
          title: 'Aegis',
          debugShowCheckedModeBanner: false,
          theme: AegisTheme.light(),
          darkTheme: AegisTheme.dark(),
          themeMode: ThemeMode.light,
          routerConfig: appRouter,
          locale: locale,
          supportedLocales: _supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Many of our 140 catalog languages aren't in
          // GlobalMaterialLocalizations / AppLocalizations. For any
          // unsupported code, fall back to English (matches
          // AppLocalizations' generated supportedLocales — currently
          // en + hi; rest of the 140 fall through to en until their
          // ARBs ship).
          localeResolutionCallback: (deviceLocale, supported) {
            if (locale != null) {
              for (final s in supported) {
                if (s.languageCode == locale.languageCode) return s;
              }
              return const Locale('en');
            }
            return null;
          },
        );
      },
    );
  }

  static final List<Locale> _supportedLocales =
      SupportedLanguages.all.map((l) => Locale(l.code)).toList(growable: false);
}
