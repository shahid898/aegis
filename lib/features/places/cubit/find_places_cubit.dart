import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/places/place.dart';
import '../../../core/places/places_repository.dart';
import '../../../core/storage/storage_service.dart';

enum FindPlacesStatus { loading, ready, empty, missingData, error }

@immutable
class FindPlacesState {
  const FindPlacesState({
    required this.status,
    required this.center,
    required this.activeCategories,
    required this.radiusKm,
    required this.places,
    this.locationFromGps = false,
    this.errorMessage,
  });

  final FindPlacesStatus status;
  final LatLng center;
  final Set<PlaceCategory> activeCategories;
  final double radiusKm;
  final List<Place> places;
  final bool locationFromGps;
  final String? errorMessage;

  FindPlacesState copyWith({
    FindPlacesStatus? status,
    LatLng? center,
    Set<PlaceCategory>? activeCategories,
    double? radiusKm,
    List<Place>? places,
    bool? locationFromGps,
    String? errorMessage,
  }) =>
      FindPlacesState(
        status: status ?? this.status,
        center: center ?? this.center,
        activeCategories: activeCategories ?? this.activeCategories,
        radiusKm: radiusKm ?? this.radiusKm,
        places: places ?? this.places,
        locationFromGps: locationFromGps ?? this.locationFromGps,
        errorMessage: errorMessage,
      );
}

/// Drives the find-nearby-places map screen. Resolves a usable
/// centre point (live GPS → onboarding region → fallback), then runs
/// [PlacesRepository.findNearby] against the on-device sqflite cache.
class FindPlacesCubit extends Cubit<FindPlacesState> {
  FindPlacesCubit({
    required PlacesRepository repository,
    required StorageService storage,
    required List<PlaceCategory> initialCategories,
    double? radiusKmOverride,
  })  : _repository = repository,
        _radiusOverride = radiusKmOverride,
        super(FindPlacesState(
          status: FindPlacesStatus.loading,
          center: _fallbackCenter(storage),
          activeCategories: initialCategories.toSet(),
          radiusKm: radiusKmOverride ?? _initialRadius(initialCategories),
          places: const [],
        )) {
    _bootstrap(initialCategories);
  }

  final PlacesRepository _repository;
  final double? _radiusOverride;

  static LatLng _fallbackCenter(StorageService s) {
    final region = s.selectedRegion;
    if (region == null) return const LatLng(20.5937, 78.9629);
    return LatLng(region.latitude, region.longitude);
  }

  static double _initialRadius(List<PlaceCategory> categories) {
    if (categories.isEmpty) return 5;
    return categories
        .map((c) => c.defaultRadiusKm)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<void> _bootstrap(List<PlaceCategory> categories) async {
    final hasData = await _repository.hasData;
    if (!hasData) {
      emit(state.copyWith(status: FindPlacesStatus.missingData));
      return;
    }
    final center = await _resolveCenter();
    await _refresh(center: center, categories: categories.toSet());
  }

  Future<LatLng> _resolveCenter() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return state.center;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return state.center;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      emit(state.copyWith(locationFromGps: true));
      return LatLng(pos.latitude, pos.longitude);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[FindPlacesCubit] GPS resolve failed: $e');
      }
      return state.center;
    }
  }

  Future<void> toggleCategory(PlaceCategory category) async {
    final next = {...state.activeCategories};
    if (!next.remove(category)) next.add(category);
    if (next.isEmpty) {
      emit(state.copyWith(activeCategories: next, places: const []));
      return;
    }
    await _refresh(center: state.center, categories: next);
  }

  Future<void> recenterOnUser() async {
    final center = await _resolveCenter();
    await _refresh(center: center, categories: state.activeCategories);
  }

  Future<void> _refresh({
    required LatLng center,
    required Set<PlaceCategory> categories,
  }) async {
    emit(state.copyWith(
      status: FindPlacesStatus.loading,
      center: center,
      activeCategories: categories,
    ));
    try {
      final radius = _radiusOverride ??
          categories
              .map((c) => c.defaultRadiusKm)
              .fold<double>(0, (a, b) => a > b ? a : b);
      final hits = await _repository.findNearby(
        categories: categories.toList(),
        center: center,
        radiusKm: radius == 0 ? 5 : radius,
      );
      emit(state.copyWith(
        status: hits.isEmpty
            ? FindPlacesStatus.empty
            : FindPlacesStatus.ready,
        places: hits,
        radiusKm: radius == 0 ? 5 : radius,
      ));
    } on Object catch (e) {
      emit(state.copyWith(
        status: FindPlacesStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }
}
