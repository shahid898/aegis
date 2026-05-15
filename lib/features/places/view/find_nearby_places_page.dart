import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/injection.dart';
import '../../../core/places/place.dart';
import '../../../core/places/places_repository.dart';
import '../../../core/storage/storage_service.dart';
import '../cubit/find_places_cubit.dart';
import '../widgets/find_nearby_places_map.dart';

/// Entry point for the find-nearby-places skill. Accepts the requested
/// categories (and optional radius) via constructor — caller is either
/// the home page CTA (defaults to shelter+hospital+water) or the
/// assistant cubit when the LLM emits a `find-nearby-places` skill
/// trigger.
class FindNearbyPlacesPage extends StatelessWidget {
  const FindNearbyPlacesPage({
    super.key,
    this.categories = const [
      PlaceCategory.shelter,
      PlaceCategory.hospital,
      PlaceCategory.waterPoint,
    ],
    this.radiusKm,
  });

  final List<PlaceCategory> categories;
  final double? radiusKm;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FindPlacesCubit(
        repository: sl<PlacesRepository>(),
        storage: sl<StorageService>(),
        initialCategories: categories,
        radiusKmOverride: radiusKm,
      ),
      child: const _FindPlacesView(),
    );
  }
}

class _FindPlacesView extends StatelessWidget {
  const _FindPlacesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: BlocBuilder<FindPlacesCubit, FindPlacesState>(
        builder: (context, state) {
          return switch (state.status) {
            FindPlacesStatus.loading when state.places.isEmpty =>
              const _CenteredMessage(
                icon: Icons.travel_explore_rounded,
                title: 'Finding nearby places…',
              ),
            FindPlacesStatus.missingData => _MissingDataView(),
            FindPlacesStatus.error => _CenteredMessage(
                icon: Icons.error_outline_rounded,
                title: 'Could not load places',
                subtitle: state.errorMessage ?? '',
              ),
            FindPlacesStatus.empty => Stack(children: [
                FindNearbyPlacesMap(
                  state: state,
                  onMarkerTap: (_) {},
                  onCall: _launchTel,
                  onToggleCategory: (c) =>
                      context.read<FindPlacesCubit>().toggleCategory(c),
                  onRecenter: () =>
                      context.read<FindPlacesCubit>().recenterOnUser(),
                ),
                _EmptyBanner(radiusKm: state.radiusKm),
              ]),
            _ => FindNearbyPlacesMap(
                state: state,
                onMarkerTap: (_) {},
                onCall: _launchTel,
                onToggleCategory: (c) =>
                    context.read<FindPlacesCubit>().toggleCategory(c),
                onRecenter: () =>
                    context.read<FindPlacesCubit>().recenterOnUser(),
              ),
          };
        },
      ),
    );
  }

  Future<void> _launchTel(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.subtitle = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingDataView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: Icons.cloud_off_rounded,
      title: 'No nearby place data yet',
      subtitle:
          'Re-run onboarding (or wait for the next sync) to download the '
          'offline place database for your area.',
    );
  }
}

class _EmptyBanner extends StatelessWidget {
  const _EmptyBanner({required this.radiusKm});
  final double radiusKm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC1E1E2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF444466), width: 0.5),
          ),
          child: Text(
            'No places within ${radiusKm.toStringAsFixed(0)} km. '
            'Try a different category.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
