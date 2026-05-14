import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'place.dart';
import 'places_database.dart';

/// Public read API around [PlacesDatabase] for the assistant + map page.
/// Singleton in DI — opens the database lazily on first call so apps that
/// never invoke the find-nearby-places skill don't pay sqflite init cost.
class PlacesRepository {
  PlacesRepository();

  PlacesDatabase? _db;
  Future<PlacesDatabase>? _opening;

  Future<PlacesDatabase> _open() {
    final cached = _db;
    if (cached != null) return Future.value(cached);
    final inFlight = _opening;
    if (inFlight != null) return inFlight;
    final future = PlacesDatabase.open();
    _opening = future;
    return future.then((db) {
      _db = db;
      _opening = null;
      return db;
    });
  }

  /// Returns `true` if the seed pass landed at least one row.
  Future<bool> get hasData async {
    try {
      final db = await _open();
      final n = await db.count();
      return n > 0;
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('[PlacesRepository] hasData failed: $e');
      }
      return false;
    }
  }

  /// Skill entry point. Returns at most [maxResults] sorted by status
  /// then haversine distance. Expands the radius by ×1.5 once on a zero
  /// result to keep the spoken response useful in sparse areas.
  Future<List<Place>> findNearby({
    required List<PlaceCategory> categories,
    required LatLng center,
    required double radiusKm,
    int maxResults = 30,
  }) async {
    final db = await _open();
    var hits = await db.queryNearby(
      categories: categories,
      center: center,
      radiusKm: radiusKm,
      maxResults: maxResults,
    );
    if (hits.isEmpty) {
      hits = await db.queryNearby(
        categories: categories,
        center: center,
        radiusKm: radiusKm * 1.5,
        maxResults: maxResults,
      );
    }
    return hits;
  }

  Future<void> close() async {
    final db = _db;
    if (db == null) return;
    _db = null;
    await db.close();
  }
}
