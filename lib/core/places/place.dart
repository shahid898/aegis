import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Lifecycle status of a place. Driven by either OSM metadata at seed time
/// or by a future status-patch channel from a backend (sprint TBD). The
/// `compromised` status is reserved for confirmed-unsafe locations (e.g.
/// shelter destroyed) and is always filtered out before being shown.
enum PlaceStatus { open, full, unknown, closed, compromised }

/// Closed catalog of POI categories the offline OSM seeder + find-nearby-places
/// skill agree on. Wire-format names match the snake_case strings stored in
/// the sqflite `places.category` column and emitted by the skill.
enum PlaceCategory {
  shelter,
  hospital,
  clinic,
  pharmacy,
  waterPoint,
  foodDistribution,
  fuelStation,
  atm,
  police,
  fireStation,
  chargingPoint,
  connectivityPoint,
  animalShelter,
  communityHub,
  supplyPoint;

  /// snake_case identifier persisted in sqflite and used in the skill JSON.
  String get wireName => switch (this) {
        PlaceCategory.shelter => 'shelter',
        PlaceCategory.hospital => 'hospital',
        PlaceCategory.clinic => 'clinic',
        PlaceCategory.pharmacy => 'pharmacy',
        PlaceCategory.waterPoint => 'water_point',
        PlaceCategory.foodDistribution => 'food_distribution',
        PlaceCategory.fuelStation => 'fuel_station',
        PlaceCategory.atm => 'atm',
        PlaceCategory.police => 'police',
        PlaceCategory.fireStation => 'fire_station',
        PlaceCategory.chargingPoint => 'charging_point',
        PlaceCategory.connectivityPoint => 'connectivity_point',
        PlaceCategory.animalShelter => 'animal_shelter',
        PlaceCategory.communityHub => 'community_hub',
        PlaceCategory.supplyPoint => 'supply_point',
      };

  static PlaceCategory? fromWire(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    for (final c in PlaceCategory.values) {
      if (c.wireName == normalized) return c;
    }
    return null;
  }

  /// Human label rendered on filter chips + detail sheets.
  String get label => switch (this) {
        PlaceCategory.shelter => 'Shelter',
        PlaceCategory.hospital => 'Hospital',
        PlaceCategory.clinic => 'Clinic',
        PlaceCategory.pharmacy => 'Pharmacy',
        PlaceCategory.waterPoint => 'Water',
        PlaceCategory.foodDistribution => 'Food',
        PlaceCategory.fuelStation => 'Fuel',
        PlaceCategory.atm => 'ATM',
        PlaceCategory.police => 'Police',
        PlaceCategory.fireStation => 'Fire Station',
        PlaceCategory.chargingPoint => 'Charging',
        PlaceCategory.connectivityPoint => 'Wifi',
        PlaceCategory.animalShelter => 'Animal Shelter',
        PlaceCategory.communityHub => 'Community Hub',
        PlaceCategory.supplyPoint => 'Supply Point',
      };

  /// Per-skill default search radius.
  double get defaultRadiusKm => switch (this) {
        PlaceCategory.shelter => 5,
        PlaceCategory.hospital => 10,
        PlaceCategory.clinic => 5,
        PlaceCategory.pharmacy => 3,
        PlaceCategory.waterPoint => 2,
        PlaceCategory.foodDistribution => 3,
        PlaceCategory.fuelStation => 5,
        PlaceCategory.atm => 2,
        PlaceCategory.police => 5,
        PlaceCategory.fireStation => 5,
        PlaceCategory.chargingPoint => 2,
        PlaceCategory.connectivityPoint => 2,
        PlaceCategory.animalShelter => 5,
        PlaceCategory.communityHub => 5,
        PlaceCategory.supplyPoint => 5,
      };

  /// Marker tint. Mirrors the skill's category-table palette.
  Color get color => switch (this) {
        PlaceCategory.shelter => const Color(0xFF2E7D32),
        PlaceCategory.hospital => const Color(0xFFC62828),
        PlaceCategory.clinic => const Color(0xFFAD1457),
        PlaceCategory.pharmacy => const Color(0xFF6A1B9A),
        PlaceCategory.waterPoint => const Color(0xFF0277BD),
        PlaceCategory.foodDistribution => const Color(0xFFE65100),
        PlaceCategory.fuelStation => const Color(0xFF37474F),
        PlaceCategory.atm => const Color(0xFF00695C),
        PlaceCategory.police => const Color(0xFF1A237E),
        PlaceCategory.fireStation => const Color(0xFFBF360C),
        PlaceCategory.chargingPoint => const Color(0xFFF9A825),
        PlaceCategory.connectivityPoint => const Color(0xFF00838F),
        PlaceCategory.animalShelter => const Color(0xFF558B2F),
        PlaceCategory.communityHub => const Color(0xFF4527A0),
        PlaceCategory.supplyPoint => const Color(0xFF4E342E),
      };

  IconData get icon => switch (this) {
        PlaceCategory.shelter => Icons.home_rounded,
        PlaceCategory.hospital => Icons.local_hospital_rounded,
        PlaceCategory.clinic => Icons.medical_services_rounded,
        PlaceCategory.pharmacy => Icons.medication_rounded,
        PlaceCategory.waterPoint => Icons.water_drop_rounded,
        PlaceCategory.foodDistribution => Icons.restaurant_rounded,
        PlaceCategory.fuelStation => Icons.local_gas_station_rounded,
        PlaceCategory.atm => Icons.atm_rounded,
        PlaceCategory.police => Icons.local_police_rounded,
        PlaceCategory.fireStation => Icons.fire_truck_rounded,
        PlaceCategory.chargingPoint => Icons.electrical_services_rounded,
        PlaceCategory.connectivityPoint => Icons.wifi_rounded,
        PlaceCategory.animalShelter => Icons.pets_rounded,
        PlaceCategory.communityHub => Icons.groups_rounded,
        PlaceCategory.supplyPoint => Icons.inventory_2_rounded,
      };

  /// Marker size tier: 44dp critical, 36dp high, 28dp medium.
  int get priority => switch (this) {
        PlaceCategory.shelter ||
        PlaceCategory.hospital ||
        PlaceCategory.waterPoint =>
          1,
        PlaceCategory.clinic ||
        PlaceCategory.pharmacy ||
        PlaceCategory.foodDistribution ||
        PlaceCategory.police ||
        PlaceCategory.fireStation =>
          2,
        _ => 3,
      };

  double get markerSize =>
      switch (priority) { 1 => 44, 2 => 36, _ => 28 };
}

/// Immutable domain entity. Row in `places` after the [PlacesDatabase]
/// finishes the haversine pass.
@immutable
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.position,
    required this.address,
    required this.distanceKm,
    required this.walkingMinutes,
    required this.drivingMinutes,
    required this.status,
    required this.features,
    required this.lastVerified,
    this.capacity,
    this.spotsAvailable,
    this.phone,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final LatLng position;
  final String address;
  final double distanceKm;
  final int walkingMinutes;
  final int drivingMinutes;
  final PlaceStatus status;
  final int? capacity;
  final int? spotsAvailable;
  final String? phone;
  final List<String> features;
  final String lastVerified;
}
