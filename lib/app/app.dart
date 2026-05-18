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
          // unsupported code, fall back to English. The `supported`
          // callback arg is the full 140-locale MaterialApp list,
          // which matches codes (e.g. `es`) that have NO ARB file —
          // returning that locale crashes `AppLocalizations.of(...)!`
          // because the delegate fails to load. Match against
          // `AppLocalizations.supportedLocales` (the generated list
          // of locales that actually have ARBs — currently en + hi)
          // instead, so unsupported picks resolve to en cleanly.
          localeResolutionCallback: (deviceLocale, supported) {
            final target = locale ?? deviceLocale;
            if (target == null) return const Locale('en');
            for (final s in AppLocalizations.supportedLocales) {
              if (s.languageCode == target.languageCode) return s;
            }
            return const Locale('en');
          },
        );
      },
    );
  }

  static final List<Locale> _supportedLocales =
      SupportedLanguages.all.map((l) => Locale(l.code)).toList(growable: false);
}
