import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'osm_place_mapper.dart';
import 'overpass_query.dart';
import 'place.dart';
import 'places_database.dart';

/// Result envelope returned to the onboarding cubit. Success carries the
/// per-category breakdown so the UI can show "shelter ×12, hospital ×3"
/// before letting the user continue.
@immutable
class OnboardingPlacesResult {
  const OnboardingPlacesResult({
    required this.success,
    this.placesCount = 0,
    this.coverageKm = 0,
    this.breakdown = const {},
    this.error,
  });

  final bool success;
  final int placesCount;
  final double coverageKm;
  final Map<String, int> breakdown;
  final String? error;
}

/// One-shot seeder for `places.db`. Runs alongside the model-pack
/// download during onboarding. Failure is non-fatal — the find-nearby-
/// places skill still works on whatever rows landed before the error,
/// and the user can re-run onboarding from settings later.
class OnboardingPlacesDownloader {
  OnboardingPlacesDownloader({this.onProgress});

  /// Optional progress hook: (message, 0.0–1.0).
  final void Function(String message, double progress)? onProgress;

  Future<OnboardingPlacesResult> download({
    required LatLng userLocation,
    double radiusKm = 25,
  }) async {
    try {
      _report('Preparing your area…', 0.05);
      final bbox = BoundingBox.fromCenter(userLocation, radiusKm: radiusKm);

      _report('Downloading place data…', 0.15);
      final rawJson = await OverpassQuery.fetch(bbox);

      _report('Processing places…', 0.55);
      final places = OsmPlaceMapper.parse(rawJson);

      _report('Building offline database…', 0.70);
      final db = await PlacesDatabase.open();

      _report('Saving ${places.length} places…', 0.85);
      await db.insertPlaces(places);
      // Leave the DB open: PlacesRepository wraps the same handle in DI.

      _report('Places ready.', 1.0);
      return OnboardingPlacesResult(
        success: true,
        placesCount: places.length,
        coverageKm: radiusKm,
        breakdown: {
          for (final c in PlaceCategory.values)
            c.wireName: places.where((p) => p.category == c).length,
        },
      );
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OnboardingPlacesDownloader] failed: $e\n$st');
      }
      return OnboardingPlacesResult(success: false, error: e.toString());
    }
  }

  void _report(String message, double progress) {
    onProgress?.call(message, progress);
  }
}
