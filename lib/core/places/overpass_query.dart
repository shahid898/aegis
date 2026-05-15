import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Axis-aligned WGS84 bounding box computed from a centre point + radius.
/// Used for the one-shot Overpass POST at onboarding. Width-by-latitude
/// correction keeps the box close to a circle far from the equator.
class BoundingBox {
  const BoundingBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  factory BoundingBox.fromCenter(LatLng center, {double radiusKm = 25}) {
    const kmPerDegLat = 111.0;
    final kmPerDegLng = 111.0 * math.cos(center.latitude * math.pi / 180);
    final dLat = radiusKm / kmPerDegLat;
    final dLng = radiusKm / kmPerDegLng;
    return BoundingBox(
      south: center.latitude - dLat,
      west: center.longitude - dLng.abs(),
      north: center.latitude + dLat,
      east: center.longitude + dLng.abs(),
    );
  }

  String toOverpassString() => '$south,$west,$north,$east';
}

/// One-shot OSM Overpass client. Free, no API key. Called exactly once per
/// onboarding session — Overpass rate limits aggressive callers, so the
/// app must not retry on a tight loop. Failures bubble up to
/// [OnboardingPlacesDownloader] which marks the seed pass as skipped.
class OverpassQuery {
  const OverpassQuery._();

  static const String endpoint = 'https://overpass-api.de/api/interpreter';

  /// Disaster-relevant Overpass QL query. Mirrors the categories the
  /// find-nearby-places skill handles. `out center body` returns the
  /// centroid for `way`/`relation` results so we can store a single
  /// (lat,lng) per row.
  static String buildQuery(BoundingBox bbox) {
    final b = bbox.toOverpassString();
    return '''
[out:json][timeout:60];
(
  node["emergency"="shelter"]($b);
  node["amenity"="shelter"]($b);
  node["social_facility"="shelter"]($b);

  node["amenity"="hospital"]($b);
  way["amenity"="hospital"]($b);

  node["amenity"="clinic"]($b);
  node["amenity"="doctors"]($b);
  node["healthcare"="clinic"]($b);

  node["amenity"="pharmacy"]($b);

  node["amenity"="drinking_water"]($b);
  node["man_made"="water_tap"]($b);
  node["emergency"="water_station"]($b);

  node["amenity"="food_bank"]($b);
  node["social_facility"="food_bank"]($b);

  node["amenity"="fuel"]($b);

  node["amenity"="atm"]($b);
  node["amenity"="bank"]($b);

  node["amenity"="police"]($b);

  node["amenity"="fire_station"]($b);
);
out center body;
''';
  }

  /// Fire the POST. Returns the raw JSON body for the mapper to parse.
  /// Times out after 90 s — Overpass occasionally hangs on large bboxes.
  static Future<String> fetch(
    BoundingBox bbox, {
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final response = await c
          .post(
            Uri.parse(endpoint),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': 'aegis-app/1.0 (offline emergency assistant)',
            },
            body: 'data=${Uri.encodeComponent(buildQuery(bbox))}',
          )
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        throw OverpassException(
          'Overpass error ${response.statusCode}: ${response.body}',
        );
      }
      return response.body;
    } finally {
      if (client == null) c.close();
    }
  }
}

class OverpassException implements Exception {
  OverpassException(this.message);
  final String message;

  @override
  String toString() => 'OverpassException: $message';
}
