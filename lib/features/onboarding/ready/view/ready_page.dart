import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/storage_service.dart';

class ReadyPage extends StatelessWidget {
  const ReadyPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                "You're ready.",
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Tap the icon anytime to ask Aegis a question. It works without internet.',
                textAlign: TextAlign.center,
                style: TextStyle(
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
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
