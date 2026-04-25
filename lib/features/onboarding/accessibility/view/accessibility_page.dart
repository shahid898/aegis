import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../models/accessibility_profile.dart';
import '../cubit/accessibility_cubit.dart';

class AccessibilityPage extends StatelessWidget {
  const AccessibilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AccessibilityCubit(sl<StorageService>()),
      child: const _AccessibilityView(),
    );
  }
}

class _AccessibilityView extends StatelessWidget {
  const _AccessibilityView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('A few questions')),
      body: SafeArea(
        child: BlocBuilder<AccessibilityCubit, AccessibilityProfile>(
          builder: (context, state) {
            final cubit = context.read<AccessibilityCubit>();
            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Text(
                    'Your answers shape how Aegis routes you in an emergency. Answers stay on this device.',
                    style: TextStyle(
                      color: AegisColors.onSurfaceMuted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _YesNoCard(
                        question: 'Do you use a wheelchair?',
                        value: state.usesWheelchair,
                        onChanged: (_) => cubit.toggleWheelchair(),
                      ),
                      const SizedBox(height: 12),
                      _YesNoCard(
                        question: 'Do you take daily medication?',
                        value: state.takesDailyMedication,
                        onChanged: (_) => cubit.toggleMedication(),
                      ),
                      const SizedBox(height: 12),
                      _YesNoCard(
                        question:
                            'Is there someone in your home who needs special help (child, elderly, disabled)?',
                        value: state.hasDependent,
                        onChanged: (_) => cubit.toggleDependent(),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: FilledButton(
                      onPressed: () async {
                        await cubit.confirm();
                        if (!context.mounted) return;
                        context.go(AppRoute.contacts.path);
                      },
                      child: const Text('Continue'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _YesNoCard extends StatelessWidget {
  const _YesNoCard({
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final String question;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: const TextStyle(fontSize: 16, height: 1.35),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Pill(
                    label: 'No',
                    selected: !value,
                    onTap: () => onChanged(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Pill(
                    label: 'Yes',
                    selected: value,
                    onTap: () => onChanged(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AegisColors.primary : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AegisColors.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
