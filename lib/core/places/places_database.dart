import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'osm_place_mapper.dart';
import 'place.dart';

/// Thin sqflite wrapper around the on-device POI cache. One table
/// (`places`) indexed on `(lat, lng)` and `(category)` so the spatial
/// pre-filter is an indexed range scan; a haversine pass in Dart finishes
/// the radius filter on the small result set. A second table
/// (`status_patches`) records future backend overrides — the seed pass
/// always sets status='unknown'.
class PlacesDatabase {
  PlacesDatabase._(this._db);

  static const String dbName = 'places.db';
  static const int schemaVersion = 1;

  final Database _db;
  Database get raw => _db;

  /// Open / create the database file under the app documents directory.
  /// Idempotent — multiple callers share the same underlying handle.
  static Future<PlacesDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$dbName';
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
    );
    return PlacesDatabase._(db);
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE places (
        id              TEXT PRIMARY KEY,
        osm_id          TEXT NOT NULL,
        name            TEXT NOT NULL,
        category        TEXT NOT NULL,
        lat             REAL NOT NULL,
        lng             REAL NOT NULL,
        address         TEXT NOT NULL DEFAULT '',
        phone           TEXT,
        features        TEXT NOT NULL DEFAULT '[]',
        status          TEXT NOT NULL DEFAULT 'unknown',
        capacity        INTEGER,
        spots_available INTEGER,
        last_verified   TEXT NOT NULL,
        patch_version   INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_places_location ON places (lat, lng)',
    );
    await db.execute(
      'CREATE INDEX idx_places_category ON places (category)',
    );
    await db.execute(
      'CREATE INDEX idx_places_status ON places (status)',
    );
    await db.execute('''
      CREATE TABLE status_patches (
        id              TEXT PRIMARY KEY,
        place_id        TEXT NOT NULL,
        status          TEXT NOT NULL,
        capacity        INTEGER,
        spots_available INTEGER,
        notes           TEXT,
        applied_at      TEXT NOT NULL,
        patch_version   INTEGER NOT NULL,
        FOREIGN KEY (place_id) REFERENCES places(id)
      )
    ''');
  }

  Future<int> count() async {
    final result = await _db.rawQuery('SELECT COUNT(*) AS n FROM places');
    return (result.first['n'] as int?) ?? 0;
  }

  Future<void> close() => _db.close();

  /// Bulk insert from the OSM seed pass. Uses REPLACE so re-running
  /// onboarding refreshes any existing rows.
  Future<void> insertPlaces(List<RawPlace> places) async {
    final batch = _db.batch();
    final now = DateTime.now().toIso8601String();
    for (final p in places) {
      batch.insert(
        'places',
        {
          'id': p.osmId,
          'osm_id': p.osmId,
          'name': p.name,
          'category': p.category.wireName,
          'lat': p.lat,
          'lng': p.lng,
          'address': p.address,
          'phone': p.phone,
          'features': jsonEncode(p.features),
          'status': 'unknown',
          'last_verified': now,
          'patch_version': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Indexed bbox pre-filter → Dart haversine → status sort. Returns at
  /// most [maxResults] rows per category, sorted by status then distance.
  Future<List<Place>> queryNearby({
    required List<PlaceCategory> categories,
    required LatLng center,
    required double radiusKm,
    int maxResults = 30,
  }) async {
    if (categories.isEmpty) return const [];
    final dLat = radiusKm / 111.0;
    final dLng =
        radiusKm / (111.0 * math.cos(center.latitude * math.pi / 180).abs());
    final placeholders = categories.map((_) => '?').join(',');
    final rows = await _db.query(
      'places',
      where: '''
        category IN ($placeholders)
        AND status != 'compromised'
        AND lat BETWEEN ? AND ?
        AND lng BETWEEN ? AND ?
      ''',
      whereArgs: [
        ...categories.map((c) => c.wireName),
        center.latitude - dLat,
        center.latitude + dLat,
        center.longitude - dLng,
        center.longitude + dLng,
      ],
    );

    final places = <Place>[];
    for (final row in rows) {
      final lat = (row['lat'] as num).toDouble();
      final lng = (row['lng'] as num).toDouble();
      final distanceKm = _haversineKm(
        center.latitude,
        center.longitude,
        lat,
        lng,
      );
      if (distanceKm > radiusKm) continue;
      final category = PlaceCategory.fromWire(row['category'] as String?);
      if (category == null) continue;
      places.add(Place(
        id: row['id'] as String,
        name: row['name'] as String,
        category: category,
        position: LatLng(lat, lng),
        address: (row['address'] as String?) ?? '',
        distanceKm: distanceKm,
        // Rough estimates: 5 km/h walk, 30 km/h drive. Good enough until a
        // routing engine is wired in.
        walkingMinutes: (distanceKm / 5 * 60).round(),
        drivingMinutes: (distanceKm / 30 * 60).round(),
        status: _decodeStatus(row['status'] as String?),
        capacity: row['capacity'] as int?,
        spotsAvailable: row['spots_available'] as int?,
        phone: row['phone'] as String?,
        features: _decodeFeatures(row['features'] as String?),
        lastVerified: (row['last_verified'] as String?) ?? '',
      ));
    }

    const statusOrder = {
      PlaceStatus.open: 0,
      PlaceStatus.unknown: 1,
      PlaceStatus.full: 2,
      PlaceStatus.closed: 3,
      PlaceStatus.compromised: 4,
    };
    places.sort((a, b) {
      final s = (statusOrder[a.status] ?? 9)
          .compareTo(statusOrder[b.status] ?? 9);
      return s != 0 ? s : a.distanceKm.compareTo(b.distanceKm);
    });
    return places.length > maxResults
        ? places.sublist(0, maxResults)
        : places;
  }

  static PlaceStatus _decodeStatus(String? raw) {
    for (final s in PlaceStatus.values) {
      if (s.name == raw) return s;
    }
    return PlaceStatus.unknown;
  }

  static List<String> _decodeFeatures(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } on FormatException {
      // tolerate corrupt rows — empty features beats a crash
    }
    return const [];
  }

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.asin(math.min(1, math.sqrt(a)));
  }
}
