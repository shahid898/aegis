import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/theme.dart';
import '../../../core/places/map_view_query.dart';
import '../../../core/places/place.dart';

/// Compact in-chat map card. Rendered inline between user + assistant
/// bubbles whenever Gemma 4 fired the `render_map_view` tool on a chat
/// turn. Drops the standalone-page chrome (filter bar, action rail,
/// list toggle) — chat surface is bandwidth-limited.
///
/// Tiles: CARTO Voyager raster basemap. OSM's tile.openstreetmap.org
/// blocks Flutter Map apps for violating their no-mobile-app policy.
/// Voyager is free for limited use and styled to match a light theme.
class InlineMapCard extends StatefulWidget {
  const InlineMapCard({
    super.key,
    required this.query,
    required this.places,
    required this.center,
    this.onPlaceTap,
    this.onCall,
    this.height = 280,
  });

  final MapViewQuery query;
  final List<Place> places;
  final LatLng center;
  final void Function(Place place)? onPlaceTap;
  final void Function(String phone)? onCall;
  final double height;

  @override
  State<InlineMapCard> createState() => _InlineMapCardState();
}

class _InlineMapCardState extends State<InlineMapCard>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  Place? _selected;

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
  void dispose() {
    _mapController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            SizedBox(
              height: widget.height,
              child: Stack(
                children: [
                  _buildMap(),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: _buildAttribution(),
                  ),
                  if (_selected != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildSelectedSheet(_selected!),
                    ),
                ],
              ),
            ),
            if (widget.places.isNotEmpty) _buildListPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final categories = widget.query.categories
        .map((c) => c.label)
        .toSet()
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          const Icon(
            Icons.map_rounded,
            size: 16,
            color: AegisColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              categories.isEmpty ? 'Nearby places' : categories,
              style: const TextStyle(
                color: AegisColors.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${widget.places.length} · '
            '${widget.query.radiusKm.toStringAsFixed(0)} km',
            style: const TextStyle(
              color: AegisColors.onSurfaceMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: 13,
        minZoom: 10,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom |
              InteractiveFlag.drag |
              InteractiveFlag.doubleTapZoom,
        ),
        onTap: (_, _) => setState(() => _selected = null),
      ),
      children: [
        TileLayer(
          // CARTO Voyager — free raster basemap with light, friendly
          // styling. Avoids OSM's tile.openstreetmap.org which now
          // hard-blocks Flutter Map apps for tile-usage policy
          // violations. Attribution rendered as a small chip below.
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/'
              '{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'app.aegis.offline',
          maxNativeZoom: 19,
          errorTileCallback: (tile, error, stack) {},
        ),
        CircleLayer(circles: [
          CircleMarker(
            point: widget.center,
            radius: widget.query.radiusKm * 1000,
            useRadiusInMeter: true,
            color: AegisColors.primary.withValues(alpha: 0.06),
            borderColor: AegisColors.primary.withValues(alpha: 0.35),
            borderStrokeWidth: 1,
          ),
        ]),
        MarkerLayer(markers: widget.places.map(_buildMarker).toList()),
        MarkerLayer(markers: [_buildUserMarker()]),
      ],
    );
  }

  Widget _buildAttribution() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '© OpenStreetMap · © CARTO',
        style: TextStyle(
          color: AegisColors.onSurfaceMuted,
          fontSize: 9,
        ),
      ),
    );
  }

  Marker _buildMarker(Place place) {
    final selected = _selected?.id == place.id;
    final size = place.category.markerSize * 0.85;
    return Marker(
      point: place.position,
      width: size + (selected ? 10 : 0),
      height: size + (selected ? 10 : 0),
      child: GestureDetector(
        onTap: () {
          setState(() => _selected = place);
          widget.onPlaceTap?.call(place);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: place.category.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: selected ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: place.category.color.withValues(alpha: 0.45),
                blurRadius: selected ? 10 : 4,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              place.category.icon,
              size: size * 0.4,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildUserMarker() {
    return Marker(
      point: widget.center,
      width: 40,
      height: 40,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40 * _pulseAnim.value,
              height: 40 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AegisColors.primary.withValues(alpha: 0.18),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: AegisColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AegisColors.primary.withValues(alpha: 0.45),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedSheet(Place place) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AegisColors.onSurfaceMuted.withValues(alpha: 0.2),
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: place.category.color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              place.category.icon,
              color: Colors.white,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    color: AegisColors.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${place.distanceKm.toStringAsFixed(1)} km · '
                  '${place.walkingMinutes} min walk',
                  style: const TextStyle(
                    color: AegisColors.onSurfaceMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (place.phone != null && widget.onCall != null)
            IconButton(
              tooltip: 'Call',
              onPressed: () => widget.onCall?.call(place.phone!),
              icon: const Icon(
                Icons.call_rounded,
                size: 18,
                color: AegisColors.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListPreview() {
    final top = widget.places.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in top)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.category.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.name,
                      style: const TextStyle(
                        color: AegisColors.onSurface,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${p.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      color: AegisColors.onSurfaceMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
