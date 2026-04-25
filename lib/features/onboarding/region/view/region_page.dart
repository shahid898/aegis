import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/geo/country_resolver.dart';
import '../../../../core/storage/storage_service.dart';
import '../cubit/region_cubit.dart';

class RegionPage extends StatelessWidget {
  const RegionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          RegionCubit(sl<StorageService>(), sl<CountryResolver>()),
      child: const _RegionView(),
    );
  }
}

class _RegionView extends StatefulWidget {
  const _RegionView();

  @override
  State<_RegionView> createState() => _RegionViewState();
}

class _RegionViewState extends State<_RegionView> {
  final _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick your region'),
        actions: [
          IconButton(
            onPressed: () async {
              final cubit = context.read<RegionCubit>();
              await cubit.useCurrentLocation();
              final point = cubit.state.pickedPoint;
              if (point != null) {
                _mapController.move(point, 10);
              }
            },
            icon: const Icon(Icons.my_location),
            tooltip: 'Use GPS',
          ),
        ],
      ),
      body: BlocBuilder<RegionCubit, RegionState>(
        builder: (context, state) {
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: state.center,
                        initialZoom: state.zoom,
                        minZoom: 2,
                        maxZoom: 16,
                        onTap: (_, point) =>
                            context.read<RegionCubit>().onTap(point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.resq.aegis',
                        ),
                        if (state.pickedPoint != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: state.pickedPoint!,
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.location_on,
                                  color: AegisColors.danger,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (state.isResolvingGps)
                      const Positioned(
                        top: 12,
                        right: 12,
                        child: _ChipBadge(label: 'Locating...'),
                      ),
                    if (state.errorMessage != null)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Material(
                          color: AegisColors.danger,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              state.errorMessage!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.region == null
                          ? 'Tap the map to select your district'
                          : state.region!.districtName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (state.pickedPoint != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${state.pickedPoint!.latitude.toStringAsFixed(3)}, ${state.pickedPoint!.longitude.toStringAsFixed(3)}',
                        style: const TextStyle(
                          color: AegisColors.onSurfaceMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: FilledButton(
                    onPressed: state.region == null
                        ? null
                        : () async {
                            await context.read<RegionCubit>().confirm();
                            if (!context.mounted) return;
                            context.go(AppRoute.download.path);
                          },
                    child: const Text('Download data for this region'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
