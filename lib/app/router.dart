import 'package:go_router/go_router.dart';

import '../features/home/view/home_page.dart';
import '../features/onboarding/accessibility/view/accessibility_page.dart';
import '../features/onboarding/contacts/view/contacts_page.dart';
import '../features/onboarding/download/view/model_download_page.dart';
import '../features/onboarding/language/view/language_page.dart';
import '../features/onboarding/permissions/view/permissions_page.dart';
import '../features/onboarding/ready/view/ready_page.dart';
import '../features/onboarding/region/view/region_page.dart';
import '../features/splash/view/splash_page.dart';

enum AppRoute {
  splash('/'),
  language('/onboarding/language'),
  region('/onboarding/region'),
  download('/onboarding/download'),
  accessibility('/onboarding/accessibility'),
  contacts('/onboarding/contacts'),
  permissions('/onboarding/permissions'),
  ready('/onboarding/ready'),
  home('/home');

  const AppRoute(this.path);
  final String path;
}

final appRouter = GoRouter(
  initialLocation: AppRoute.splash.path,
  routes: [
    GoRoute(
      path: AppRoute.splash.path,
      builder: (_, _) => const SplashPage(),
    ),
    GoRoute(
      path: AppRoute.language.path,
      builder: (_, _) => const LanguagePage(),
    ),
    GoRoute(
      path: AppRoute.region.path,
      builder: (_, _) => const RegionPage(),
    ),
    GoRoute(
      path: AppRoute.download.path,
      builder: (_, _) => const ModelDownloadPage(),
    ),
    GoRoute(
      path: AppRoute.accessibility.path,
      builder: (_, _) => const AccessibilityPage(),
    ),
    GoRoute(
      path: AppRoute.contacts.path,
      builder: (_, _) => const ContactsPage(),
    ),
    GoRoute(
      path: AppRoute.permissions.path,
      builder: (_, _) => const PermissionsPage(),
    ),
    GoRoute(
      path: AppRoute.ready.path,
      builder: (_, _) => const ReadyPage(),
    ),
    GoRoute(
      path: AppRoute.home.path,
      builder: (_, _) => const HomePage(),
    ),
  ],
);
