import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/di/injection.dart';
import '../../../core/storage/storage_service.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../cubit/splash_cubit.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SplashCubit(sl<StorageService>())..decide(),
      child: BlocListener<SplashCubit, SplashState>(
        listener: (context, state) {
          switch (state) {
            case SplashGoToOnboarding():
              context.go(AppRoute.language.path);
            case SplashGoToHome():
              context.go(AppRoute.home.path);
            case SplashInitial():
              break;
          }
        },
        child: const _SplashView(),
      ),
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AegisColors.primaryDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: AegisColors.accent,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_moon_outlined,
                size: 54,
                color: AegisColors.primaryDark,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              AppLocalizations.of(context).appName,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).splashTagline,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.75),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
