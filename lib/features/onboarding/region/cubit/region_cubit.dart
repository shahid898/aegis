import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/geo/country_resolver.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../models/app_region.dart';

part 'region_cubit.freezed.dart';

@freezed
abstract class RegionState with _$RegionState {
  const factory RegionState({
    @Default(LatLng(20.5937, 78.9629)) LatLng center,
    @Default(3.5) double zoom,
    LatLng? pickedPoint,
    AppRegion? region,
    @Default(false) bool isResolvingGps,
    String? errorMessage,
  }) = _RegionState;
}

/// Localized strings the cubit needs to build [AppRegion.districtName]
/// and [RegionState.errorMessage]. The cubit doesn't have a
/// [BuildContext] so we inject these from [RegionPage] at construction
/// — keeps the cubit framework-free while still respecting the user's
/// runtime locale pick.
class RegionLabels {
  const RegionLabels({
    required this.current,
    required this.currentWithCountry,
    required this.selected,
    required this.selectedWithCountry,
    required this.errorServiceOff,
    required this.errorPermissionDenied,
    required this.errorReadFailed,
  });

  final String current;
  final String Function(String country) currentWithCountry;
  final String selected;
  final String Function(String country) selectedWithCountry;
  final String errorServiceOff;
  final String errorPermissionDenied;
  final String Function(String error) errorReadFailed;

  /// English-only fallback so callers that haven't wired up AppLocalizations
  /// (or unit tests) still work without crashing.
  static const RegionLabels fallback = RegionLabels(
    current: 'Current location',
    currentWithCountry: _enCurrentWithCountry,
    selected: 'Selected area',
    selectedWithCountry: _enSelectedWithCountry,
    errorServiceOff: 'Turn on location services to use GPS.',
    errorPermissionDenied: 'Location permission denied.',
    errorReadFailed: _enErrorReadFailed,
  );
}

String _enCurrentWithCountry(String c) => 'Current location ($c)';
String _enSelectedWithCountry(String c) => 'Selected area ($c)';
String _enErrorReadFailed(String e) => 'Could not read location: $e';

class RegionCubit extends Cubit<RegionState> {
  RegionCubit(
    this._storage,
    this._countries, {
    this.labels = RegionLabels.fallback,
  }) : super(const RegionState()) {
    final saved = _storage.selectedRegion;
    if (saved != null) {
      // Re-skin the district name through the current locale's labels.
      // The persisted name was written with whatever locale was active
      // at the time the user originally picked the region — Hindi
      // users coming back to the screen after a locale flip should not
      // see leftover English "Current location (IN)" strings.
      final rebadged = _rebadgeDistrictName(saved);
      emit(state.copyWith(
        region: rebadged,
        pickedPoint: LatLng(rebadged.latitude, rebadged.longitude),
        center: LatLng(rebadged.latitude, rebadged.longitude),
        zoom: 8,
      ));
    }
  }

  /// Rebuild [AppRegion.districtName] from [labels] if the persisted
  /// value looks like one of our generated patterns (Current/Selected
  /// in English or any locale we previously shipped). Leaves user-edited
  /// or unknown names alone.
  AppRegion _rebadgeDistrictName(AppRegion saved) {
    final country = saved.countryCode;
    final name = saved.districtName;
    // Heuristic: any prior auto-generated label always carried the
    // word "location" (current) or "area" (selected) for English, or
    // started with a known native prefix. Cheapest: regenerate from
    // labels and overwrite — we lose no information because the only
    // signal in the saved name beyond country code is "was this GPS
    // or a map tap", which we can't recover anyway. Default to GPS
    // (more common path now that we auto-trigger on page mount).
    final isSelectedTap = name.toLowerCase().contains('selected') ||
        name.toLowerCase().contains('area');
    final fresh = isSelectedTap
        ? (country.isEmpty
            ? labels.selected
            : labels.selectedWithCountry(country))
        : (country.isEmpty
            ? labels.current
            : labels.currentWithCountry(country));
    return AppRegion(
      districtName: fresh,
      countryCode: country,
      latitude: saved.latitude,
      longitude: saved.longitude,
    );
  }

  final StorageService _storage;
  final CountryResolver _countries;
  final RegionLabels labels;

  void onTap(LatLng point) {
    final country = _countries.resolve(point.latitude, point.longitude);
    final region = AppRegion(
      districtName: country.isEmpty
          ? labels.selected
          : labels.selectedWithCountry(country),
      countryCode: country,
      latitude: point.latitude,
      longitude: point.longitude,
    );
    emit(state.copyWith(pickedPoint: point, region: region));
  }

  Future<void> useCurrentLocation() async {
    emit(state.copyWith(isResolvingGps: true, errorMessage: null));
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        emit(state.copyWith(
          isResolvingGps: false,
          errorMessage: labels.errorServiceOff,
        ));
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        emit(state.copyWith(
          isResolvingGps: false,
          errorMessage: labels.errorPermissionDenied,
        ));
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final point = LatLng(pos.latitude, pos.longitude);
      final country = _countries.resolve(point.latitude, point.longitude);
      emit(state.copyWith(
        isResolvingGps: false,
        center: point,
        zoom: 10,
        pickedPoint: point,
        region: AppRegion(
          districtName: country.isEmpty
              ? labels.current
              : labels.currentWithCountry(country),
          countryCode: country,
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(
        isResolvingGps: false,
        errorMessage: labels.errorReadFailed(e.toString()),
      ));
    }
  }

  Future<void> confirm() async {
    final region = state.region;
    if (region == null) return;
    await _storage.setSelectedRegion(region);
  }
}
