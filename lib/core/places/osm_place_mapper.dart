import 'dart:convert';

import 'place.dart';

/// Raw, pre-DB representation of one OSM element after mapping. The
/// downloader writes these into [PlacesDatabase] as rows; once persisted
/// they come back as full [Place] entities with distance fields filled in.
class RawPlace {
  const RawPlace({
    required this.osmId,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.address,
    required this.features,
    this.phone,
  });

  final String osmId;
  final String name;
  final PlaceCategory category;
  final double lat;
  final double lng;
  final String address;
  final String? phone;
  final List<String> features;
}

/// Translates OSM tag soup into the closed [PlaceCategory] catalog.
class OsmPlaceMapper {
  const OsmPlaceMapper._();

  static PlaceCategory? mapCategory(Map<String, dynamic> tags) {
    final emergency = tags['emergency'] as String?;
    final amenity = tags['amenity'] as String?;
    final social = tags['social_facility'] as String?;
    final healthcare = tags['healthcare'] as String?;
    final manMade = tags['man_made'] as String?;

    if (emergency == 'shelter' ||
        amenity == 'shelter' ||
        social == 'shelter') {
      return PlaceCategory.shelter;
    }
    if (amenity == 'hospital') return PlaceCategory.hospital;
    if (amenity == 'clinic' ||
        amenity == 'doctors' ||
        healthcare == 'clinic') {
      return PlaceCategory.clinic;
    }
    if (amenity == 'pharmacy') return PlaceCategory.pharmacy;
    if (amenity == 'drinking_water' ||
        manMade == 'water_tap' ||
        emergency == 'water_station') {
      return PlaceCategory.waterPoint;
    }
    if (amenity == 'food_bank' || social == 'food_bank') {
      return PlaceCategory.foodDistribution;
    }
    if (amenity == 'fuel') return PlaceCategory.fuelStation;
    if (amenity == 'atm' || amenity == 'bank') return PlaceCategory.atm;
    if (amenity == 'police') return PlaceCategory.police;
    if (amenity == 'fire_station') return PlaceCategory.fireStation;
    return null;
  }

  static List<String> extractFeatures(Map<String, dynamic> tags) {
    final features = <String>[];
    if (tags['wheelchair'] == 'yes' || tags['wheelchair'] == 'designated') {
      features.add('wheelchair');
    }
    if (tags['generator:source'] != null ||
        tags['backup_generator'] == 'yes') {
      features.add('generator');
    }
    if (tags['healthcare'] != null || tags['medical'] == 'yes') {
      features.add('medical');
    }
    if (tags['dog'] == 'yes' || tags['animals'] == 'yes') {
      features.add('pets');
    }
    if (tags['opening_hours'] == '24/7') features.add('24hr');
    if (tags['hearing_loop'] == 'yes') features.add('hearing_loop');
    return features;
  }

  static String buildAddress(Map<String, dynamic> tags) {
    final parts = <String>[];
    final housenumber = tags['addr:housenumber'] as String?;
    final street = tags['addr:street'] as String?;
    final city = tags['addr:city'] as String?;
    if (housenumber != null && street != null) {
      parts.add('$housenumber $street');
    } else if (street != null) {
      parts.add(street);
    }
    if (city != null) parts.add(city);
    return parts.join(', ');
  }

  /// Parse the Overpass JSON envelope into [RawPlace] rows. Silently
  /// skips elements that don't map to any [PlaceCategory] or lack
  /// coordinates — the seed pass must be tolerant of OSM data drift.
  static List<RawPlace> parse(String rawJson) {
    final data = jsonDecode(rawJson) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? const [];
    final places = <RawPlace>[];

    for (final element in elements) {
      if (element is! Map<String, dynamic>) continue;
      final tags = (element['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      final category = mapCategory(tags);
      if (category == null) continue;

      double? lat;
      double? lng;
      if (element['type'] == 'node') {
        lat = (element['lat'] as num?)?.toDouble();
        lng = (element['lon'] as num?)?.toDouble();
      } else if (element['center'] is Map) {
        final center = element['center'] as Map;
        lat = (center['lat'] as num?)?.toDouble();
        lng = (center['lon'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;

      final name = (tags['name'] as String?) ??
          (tags['operator'] as String?) ??
          category.label;

      places.add(RawPlace(
        osmId: '${element['type']}_${element['id']}',
        name: name,
        category: category,
        lat: lat,
        lng: lng,
        address: buildAddress(tags),
        phone: (tags['phone'] as String?) ??
            (tags['contact:phone'] as String?),
        features: extractFeatures(tags),
      ));
    }
    return places;
  }
}
