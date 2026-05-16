import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../l10n/generated/app_localizations.dart';

class ReadyPage extends StatelessWidget {
  const ReadyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: AegisColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AegisColors.primary.withValues(alpha: 0.35),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 72,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                l.readyTitle,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 12),
              Text(
                l.readyBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: AegisColors.onSurfaceMuted,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await sl<StorageService>().setOnboardingCompleted(true);
                  if (!context.mounted) return;
                  context.go(AppRoute.home.path);
                },
                child: Text(l.actionStart),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
