import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/places/place.dart';
import '../cubit/find_places_cubit.dart';

/// Map surface consumed by [FindNearbyPlacesPage]. Renders the user
/// position, search radius, category filter bar, marker layer, and a
/// detail sheet on tap. Tiles come from OpenStreetMap's public tile
/// server — when fully offline this layer fails gracefully and the user
/// still sees markers/list on a grey background.
class FindNearbyPlacesMap extends StatefulWidget {
  const FindNearbyPlacesMap({
    super.key,
    required this.state,
    required this.onMarkerTap,
    required this.onCall,
    required this.onToggleCategory,
    required this.onRecenter,
  });

  final FindPlacesState state;
  final void Function(Place place) onMarkerTap;
  final void Function(String phone) onCall;
  final void Function(PlaceCategory category) onToggleCategory;
  final VoidCallback onRecenter;

  @override
  State<FindNearbyPlacesMap> createState() => _FindNearbyPlacesMapState();
}

class _FindNearbyPlacesMapState extends State<FindNearbyPlacesMap>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  Place? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant FindNearbyPlacesMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.center != widget.state.center) {
      _mapController.move(widget.state.center, _mapController.camera.zoom);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Stack(
      children: [
        _buildMap(state),
        _buildCategoryBar(state),
        _buildActionRail(),
        if (_selectedPlace != null) _buildDetailSheet(_selectedPlace!),
        _buildBottomHud(state),
      ],
    );
  }

  Widget _buildMap(FindPlacesState state) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: state.center,
        initialZoom: 14,
        minZoom: 10,
        maxZoom: 18,
        onTap: (_, _) => setState(() => _selectedPlace = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'app.aegis.offline',
          maxNativeZoom: 19,
          errorTileCallback: (tile, error, stack) {
            // Stay silent — offline launches paint a grey background.
          },
        ),
        CircleLayer(circles: [
          CircleMarker(
            point: state.center,
            radius: state.radiusKm * 1000,
            useRadiusInMeter: true,
            color: const Color(0x141565C0),
            borderColor: const Color(0x401565C0),
            borderStrokeWidth: 1,
          ),
        ]),
        MarkerLayer(
          markers: state.places.map(_buildPlaceMarker).toList(),
        ),
        MarkerLayer(markers: [_buildUserMarker(state.center)]),
      ],
    );
  }

  Marker _buildPlaceMarker(Place place) {
    final size = place.category.markerSize;
    final isSelected = _selectedPlace?.id == place.id;
    return Marker(
      point: place.position,
      width: size + (isSelected ? 12 : 0),
      height: size + (isSelected ? 12 : 0),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedPlace = place);
          widget.onMarkerTap(place);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: place.category.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: _statusBorderColor(place.status),
              width: isSelected ? 3 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: place.category.color.withValues(alpha: 0.4),
                blurRadius: isSelected ? 12 : 4,
                spreadRadius: isSelected ? 2 : 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              place.category.icon,
              size: size * 0.45,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildUserMarker(LatLng center) {
    return Marker(
      point: center,
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 48 * _pulseAnim.value,
              height: 48 * _pulseAnim.value,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x301565C0),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBar(FindPlacesState state) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: PlaceCategory.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final cat = PlaceCategory.values[i];
            final active = state.activeCategories.contains(cat);
            final count = state.places.where((p) => p.category == cat).length;
            return GestureDetector(
              onTap: () => widget.onToggleCategory(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: active ? cat.color : const Color(0xFF2A2A3E),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: active ? cat.color : const Color(0xFF444466),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat.icon, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      cat.label,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionRail() {
    return Positioned(
      bottom: 180,
      right: 16,
      child: Column(
        children: [
          _fab(
            icon: Icons.my_location_rounded,
            tooltip: 'Centre on me',
            onTap: widget.onRecenter,
          ),
          const SizedBox(height: 8),
          _fab(
            icon: Icons.close_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _fab({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A3E),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF444466)),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8),
            ],
          ),
          child: Icon(icon, color: Colors.white70, size: 20),
        ),
      ),
    );
  }

  Widget _buildDetailSheet(Place place) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: place.category.color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      place.category.icon,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            _statusBadge(place.status),
                            const SizedBox(width: 8),
                            Text(
                              place.category.label,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _selectedPlace = null),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF252535),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statCell(
                    Icons.directions_walk_rounded,
                    '${place.walkingMinutes} min',
                    'walk',
                  ),
                  _divider(),
                  _statCell(
                    Icons.directions_car_rounded,
                    '${place.drivingMinutes} min',
                    'drive',
                  ),
                  _divider(),
                  _statCell(
                    Icons.straighten_rounded,
                    '${place.distanceKm.toStringAsFixed(1)} km',
                    'away',
                  ),
                ],
              ),
            ),
            if (place.address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Colors.white38,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        place.address,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      icon: Icons.alt_route_rounded,
                      label: 'Directions',
                      color: const Color(0xFF1565C0),
                      onTap: () {},
                    ),
                  ),
                  if (place.phone != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        icon: Icons.call_rounded,
                        label: 'Call',
                        color: const Color(0xFF2E7D32),
                        onTap: () => widget.onCall(place.phone!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomHud(FindPlacesState state) {
    return Positioned(
      bottom: 24,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC1E1E2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF333355), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${state.places.length} places · '
              '${state.radiusKm.toStringAsFixed(0)} km radius'
              '${state.locationFromGps ? "" : " · region location"}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() =>
      Container(width: 0.5, height: 28, color: Colors.white12);

  Widget _statCell(IconData icon, String value, String label) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      );

  Widget _statusBadge(PlaceStatus status) {
    final (fg, bg, text) = switch (status) {
      PlaceStatus.open => (
          const Color(0xFF81C784),
          const Color(0xFF1B5E20),
          'Open',
        ),
      PlaceStatus.full => (
          const Color(0xFFFFB74D),
          const Color(0xFF7F3800),
          '⚠ Full',
        ),
      PlaceStatus.unknown => (
          Colors.white70,
          const Color(0xFF2A3A40),
          'Unverified',
        ),
      PlaceStatus.closed => (
          const Color(0xFFEF9A9A),
          const Color(0xFF5C0E0E),
          'Closed',
        ),
      PlaceStatus.compromised => (Colors.red, Colors.red, ''),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );

  Color _statusBorderColor(PlaceStatus status) => switch (status) {
        PlaceStatus.open => Colors.white30,
        PlaceStatus.full => const Color(0xFFFF6F00),
        PlaceStatus.unknown => Colors.white12,
        PlaceStatus.closed => const Color(0xFFB71C1C),
        PlaceStatus.compromised => Colors.red,
      };
}
