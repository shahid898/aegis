import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../core/voice/model_registry.dart';
import '../../../../core/voice/tts_service.dart';
import '../../../../models/language_option.dart';
import '../cubit/language_cubit.dart';

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LanguageCubit(
        sl<StorageService>(),
        sl<TtsService>(),
        sl<ModelRegistry>(),
      ),
      child: const _LanguageView(),
    );
  }
}

class _LanguageView extends StatelessWidget {
  const _LanguageView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<LanguageCubit, LanguageState>(
          listenWhen: (p, n) =>
              n.sampleMessage != null && p.sampleMessage != n.sampleMessage,
          listener: (context, state) {
            final msg = state.sampleMessage;
            if (msg == null) return;
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(content: Text(msg)));
          },
          builder: (context, state) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose your language',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      if (state.detected != null)
                        Text(
                          "We detected ${state.detected!.englishName}. Confirm or pick another.",
                          style: const TextStyle(
                            color: AegisColors.onSurfaceMuted,
                            height: 1.35,
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: context.read<LanguageCubit>().search,
                        decoration: InputDecoration(
                          hintText: 'Search 140 languages',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final lang = state.filtered[i];
                      final isSelected = state.selected?.code == lang.code;
                      return _LanguageTile(
                        language: lang,
                        isSelected: isSelected,
                        onTap: () =>
                            context.read<LanguageCubit>().select(lang),
                        onPlay: () =>
                            context.read<LanguageCubit>().playSample(lang),
                      );
                    },
                  ),
                ),
                _BottomBar(
                  enabled: state.selected != null,
                  label:
                      'Continue${state.selected == null ? '' : ' in ${state.selected!.nativeName}'}',
                  onTap: () async {
                    await context.read<LanguageCubit>().confirm();
                    if (!context.mounted) return;
                    context.go(AppRoute.region.path);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.isSelected,
    required this.onTap,
    required this.onPlay,
  });

  final LanguageOption language;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AegisColors.primary.withValues(alpha: 0.08)
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.nativeName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      language.englishName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AegisColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hear sample',
                icon: const Icon(Icons.volume_up_outlined),
                onPressed: onPlay,
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color:
                    isSelected ? AegisColors.primary : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: FilledButton(
          onPressed: enabled ? onTap : null,
          child: Text(label),
        ),
      ),
    );
  }
}
