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

class RegionCubit extends Cubit<RegionState> {
  RegionCubit(this._storage, this._countries) : super(const RegionState()) {
    final saved = _storage.selectedRegion;
    if (saved != null) {
      emit(state.copyWith(
        region: saved,
        pickedPoint: LatLng(saved.latitude, saved.longitude),
        center: LatLng(saved.latitude, saved.longitude),
        zoom: 8,
      ));
    }
  }

  final StorageService _storage;
  final CountryResolver _countries;

  void onTap(LatLng point) {
    final country = _countries.resolve(point.latitude, point.longitude);
    final region = AppRegion(
      districtName: country.isEmpty
          ? 'Selected area'
          : 'Selected area ($country)',
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
          errorMessage: 'Turn on location services to use GPS.',
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
          errorMessage: 'Location permission denied.',
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
              ? 'Current location'
              : 'Current location ($country)',
          countryCode: country,
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(
        isResolvingGps: false,
        errorMessage: 'Could not read location: $e',
      ));
    }
  }

  Future<void> confirm() async {
    final region = state.region;
    if (region == null) return;
    await _storage.setSelectedRegion(region);
  }
}
