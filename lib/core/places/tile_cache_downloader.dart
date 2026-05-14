import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

/// Shared identifiers for the offline tile pipeline.
class TileCacheConfig {
  const TileCacheConfig._();

  /// FMTC store name. Single store keeps the whole offline basemap.
  static const String storeName = 'aegis_offline_tiles';

  /// Tile URL template. CARTO Voyager raster — free for limited use,
  /// matches the light theme. Subdomains `a-d` provide round-robin
  /// distribution. Attribution is rendered by the inline map card.
  static const String urlTemplate =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/'
      '{z}/{x}/{y}.png';

  static const List<String> subdomains = ['a', 'b', 'c', 'd'];

  /// User-Agent token the tile provider sends to CARTO. Useful for
  /// CARTO's abuse-monitoring; pick the package id, not "flutter_map".
  static const String userAgentPackageName = 'app.aegis.offline';
}

/// Result envelope returned to the onboarding cubit. Failure is
/// non-fatal — the inline map card falls back to live tiles + the
/// cache fills opportunistically as the user pans.
@immutable
class TileCacheResult {
  const TileCacheResult({
    required this.success,
    this.tilesCached = 0,
    this.bytesCached = 0,
    this.error,
  });

  final bool success;
  final int tilesCached;
  final int bytesCached;
  final String? error;
}

/// Walks the tile pyramid for the user's region during onboarding and
/// stashes every tile in the FMTC ObjectBox store so the inline map
/// renders fully offline thereafter.
class TileCacheDownloader {
  TileCacheDownloader({this.onProgress});

  /// Optional progress hook: (message, 0.0–1.0).
  final void Function(String message, double progress)? onProgress;

  /// Coverage radius in km from the centre point. Matches the OSM
  /// Overpass POI seed for consistency.
  static const double coverageRadiusKm = 25;

  /// Min / max zoom to pre-cache. 11 = city overview, 16 = street-level
  /// detail. Total tiles for a 25 km × 25 km bbox at zoom 11-16 is
  /// roughly 2.5k tiles (~30 MB raster).
  static const int minZoom = 11;
  static const int maxZoom = 16;

  Future<TileCacheResult> download({required LatLng userLocation}) async {
    try {
      _report('Preparing offline map…', 0.02);
      final store = FMTCStore(TileCacheConfig.storeName);
      await store.manage.create();

      final region = _bboxFromCenter(userLocation, coverageRadiusKm);
      final downloadable = region.toDownloadable(
        minZoom: minZoom,
        maxZoom: maxZoom,
        options: TileLayer(
          urlTemplate: TileCacheConfig.urlTemplate,
          subdomains: TileCacheConfig.subdomains,
          userAgentPackageName: TileCacheConfig.userAgentPackageName,
        ),
      );

      _report('Downloading map tiles…', 0.05);
      final (:tileEvents, :downloadProgress) = store.download.startForeground(
        region: downloadable,
        parallelThreads: 4,
        // CARTO rate-limits aggressive scrapers — keep it tame.
        rateLimit: 50,
        skipExistingTiles: true,
        skipSeaTiles: true,
      );
      // Drop tileEvents — we only care about overall progress. Listen
      // and discard so the stream completes cleanly.
      final tileSub = tileEvents.listen((_) {});

      DownloadProgress? last;
      await for (final progress in downloadProgress) {
        last = progress;
        final pct = progress.percentageProgress;
        _report(
          'Downloading map tiles… '
          '${progress.attemptedTilesCount}/${progress.maxTilesCount}',
          0.05 + (pct / 100) * 0.93,
        );
      }
      await tileSub.cancel();

      final tilesCached = last?.successfulTilesCount ?? 0;
      final bytesCached = last?.successfulTilesSize.toInt() ?? 0;
      _report('Map ready ($tilesCached tiles).', 1.0);
      return TileCacheResult(
        success: true,
        tilesCached: tilesCached,
        bytesCached: bytesCached,
      );
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[TileCacheDownloader] failed: $e\n$st');
      }
      return TileCacheResult(success: false, error: e.toString());
    }
  }

  /// Build a rectangular FMTC region centred on [center] with [radiusKm]
  /// half-side length. Width-by-latitude correction keeps the box close
  /// to a square far from the equator.
  static RectangleRegion _bboxFromCenter(LatLng center, double radiusKm) {
    const kmPerDegLat = 111.0;
    final kmPerDegLng = (kmPerDegLat *
            (1 - 0.0067 * (1 - (center.latitude.abs() / 90))))
        .abs();
    final dLat = radiusKm / kmPerDegLat;
    final dLng = radiusKm / kmPerDegLng;
    return RectangleRegion(
      LatLngBounds(
        LatLng(center.latitude - dLat, center.longitude - dLng.abs()),
        LatLng(center.latitude + dLat, center.longitude + dLng.abs()),
      ),
    );
  }

  void _report(String message, double progress) {
    onProgress?.call(message, progress);
  }
}
