import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../cubit/permissions_cubit.dart';

class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PermissionsCubit(),
      child: const _PermissionsView(),
    );
  }
}

class _PermissionsView extends StatelessWidget {
  const _PermissionsView();

  static const _copy = <AegisPermission, (String, String, IconData)>{
    AegisPermission.microphone: (
      'Microphone',
      'Needed to hear your question and transcribe it on-device.',
      Icons.mic_none,
    ),
    AegisPermission.camera: (
      'Camera',
      'Needed to scan wounds, medicine labels, and surroundings offline.',
      Icons.camera_alt_outlined,
    ),
    AegisPermission.location: (
      'Location',
      'Needed to recommend routes and nearby shelters in your area.',
      Icons.location_on_outlined,
    ),
    AegisPermission.notifications: (
      'Notifications',
      'Needed to deliver emergency briefings and beacon alerts.',
      Icons.notifications_none,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: SafeArea(
        child: BlocBuilder<PermissionsCubit, PermissionsState>(
          builder: (context, state) {
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: AegisPermission.values.map((perm) {
                      final copy = _copy[perm]!;
                      final status =
                          state.statuses[perm] ?? PermissionStatus.denied;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PermissionCard(
                          title: copy.$1,
                          description: copy.$2,
                          icon: copy.$3,
                          status: status,
                          onRequest: () =>
                              context.read<PermissionsCubit>().request(perm),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: FilledButton(
                      onPressed: () => context.go(AppRoute.ready.path),
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

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.status,
    required this.onRequest,
  });

  final String title;
  final String description;
  final IconData icon;
  final PermissionStatus status;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final granted = status.isGranted || status.isLimited;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AegisColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AegisColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AegisColors.onSurfaceMuted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (granted)
                    const Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: AegisColors.primary, size: 18),
                        SizedBox(width: 6),
                        Text('Allowed',
                            style: TextStyle(color: AegisColors.primary)),
                      ],
                    )
                  else
                    OutlinedButton(
                      onPressed: status.isPermanentlyDenied
                          ? openAppSettings
                          : onRequest,
                      child: Text(
                        status.isPermanentlyDenied
                            ? 'Open settings'
                            : 'Allow',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
