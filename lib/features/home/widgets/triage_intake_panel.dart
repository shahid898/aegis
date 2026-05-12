import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Triage intake card. Pure Flutter — no A2UI surface. The cubit owns
/// the three pieces of evidence (text / photo / audio) as plain
/// fields; this widget just renders them and routes pill taps back to
/// the cubit via the supplied callbacks.
class TriageIntakePanel extends StatelessWidget {
  const TriageIntakePanel({
    super.key,
    required this.text,
    required this.hasPhoto,
    required this.hasAudio,
    required this.imagePreview,
    required this.onTextRequested,
    required this.onPhotoRequested,
    required this.onAudioRequested,
    required this.onSubmit,
    required this.canSubmit,
  });

  final String text;
  final bool hasPhoto;
  final bool hasAudio;
  final Uint8List? imagePreview;
  final VoidCallback onTextRequested;
  final VoidCallback onPhotoRequested;
  final VoidCallback onAudioRequested;
  final VoidCallback onSubmit;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AegisColors.onSurfaceMuted.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.medical_information_outlined,
                  size: 20,
                  color: AegisColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Triage intake',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Attach a photo, voice note, or describe the scene.',
              style: TextStyle(
                fontSize: 13,
                color: AegisColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _IntakeChip(
                  icon: Icons.short_text,
                  label: text.isEmpty ? 'Text' : 'Text · attached',
                  attached: text.isNotEmpty,
                  onTap: onTextRequested,
                ),
                _IntakeChip(
                  icon: Icons.photo_camera_outlined,
                  label: hasPhoto ? 'Photo · attached' : 'Photo',
                  attached: hasPhoto,
                  onTap: onPhotoRequested,
                ),
                _IntakeChip(
                  icon: Icons.mic_none_outlined,
                  label: hasAudio ? 'Voice · attached' : 'Voice',
                  attached: hasAudio,
                  onTap: onAudioRequested,
                ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AegisColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
            if (imagePreview != null && imagePreview!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Image.memory(imagePreview!, fit: BoxFit.cover),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: canSubmit ? onSubmit : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Analyse with Aegis'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntakeChip extends StatelessWidget {
  const _IntakeChip({
    required this.icon,
    required this.label,
    required this.attached,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool attached;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = attached ? AegisColors.primary : AegisColors.onSurfaceMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
