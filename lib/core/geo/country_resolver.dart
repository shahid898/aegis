/// Bundled GPS → ISO 3166-1 alpha-2 country resolver.
///
/// Model-pack selection is keyed off country, so we only need a coarse
/// mapping that works offline with zero network calls. We use axis-aligned
/// bounding boxes for ~60 countries — good enough for picking a download
/// pack and trivially fast (no polygon tests, no external assets).
///
/// When a point matches multiple boxes we pick the smallest by area, which
/// biases toward inner countries (e.g. NP over IN/CN) where boxes overlap.
library;

class _CountryBox {
  const _CountryBox(this.code, this.south, this.north, this.west, this.east);
  final String code;
  final double south;
  final double north;
  final double west;
  final double east;

  bool contains(double lat, double lng) {
    if (lat < south || lat > north) return false;
    if (west <= east) {
      return lng >= west && lng <= east;
    }
    // Antimeridian-crossing box (not used today, but correct if added).
    return lng >= west || lng <= east;
  }

  double get area => (north - south) * (east - west).abs();
}

class CountryResolver {
  const CountryResolver();

  /// Returns the 2-letter ISO country code for ([lat], [lng]), or an
  /// empty string when nothing matches.
  String resolve(double lat, double lng) {
    _CountryBox? best;
    double bestArea = double.infinity;
    for (final box in _boxes) {
      if (!box.contains(lat, lng)) continue;
      if (box.area < bestArea) {
        best = box;
        bestArea = box.area;
      }
    }
    return best?.code ?? '';
  }

  // Boxes are intentionally coarse (lat/lng in degrees, WGS84).
  // Order does not matter — we always pick the smallest containing box.
  static const List<_CountryBox> _boxes = [
    // South Asia
    _CountryBox('IN',  6.5,  37.0,  68.0,  97.5),
    _CountryBox('PK', 23.5,  37.0,  60.5,  77.0),
    _CountryBox('BD', 20.5,  26.7,  88.0,  92.7),
    _CountryBox('LK',  5.8,  10.0,  79.6,  82.0),
    _CountryBox('NP', 26.3,  30.5,  80.0,  88.3),
    _CountryBox('BT', 26.7,  28.4,  88.7,  92.2),
    _CountryBox('MV', -1.0,   7.3,  72.0,  74.0),

    // East & Southeast Asia
    _CountryBox('CN', 18.0,  53.5,  73.5, 135.0),
    _CountryBox('JP', 24.0,  46.0, 122.5, 153.0),
    _CountryBox('KR', 33.0,  39.0, 124.5, 132.0),
    _CountryBox('ID',-11.0,   6.2,  95.0, 141.2),
    _CountryBox('MY',  0.8,   7.5,  99.5, 119.5),
    _CountryBox('SG',  1.1,   1.5, 103.6, 104.1),
    _CountryBox('TH',  5.6,  20.5,  97.3, 105.7),
    _CountryBox('PH',  4.5,  21.3, 116.0, 127.0),
    _CountryBox('VN',  8.2,  23.4, 102.1, 109.5),
    _CountryBox('MM',  9.8,  28.5,  92.2, 101.2),
    _CountryBox('KH', 10.4,  14.7, 102.3, 107.6),
    _CountryBox('LA', 13.9,  22.5, 100.0, 107.7),

    // Middle East
    _CountryBox('AE', 22.6,  26.1,  51.5,  56.4),
    _CountryBox('SA', 16.3,  32.2,  34.5,  55.7),
    _CountryBox('EG', 22.0,  31.7,  24.7,  36.9),
    _CountryBox('JO', 29.2,  33.4,  34.9,  39.3),
    _CountryBox('QA', 24.5,  26.2,  50.7,  51.7),
    _CountryBox('KW', 28.5,  30.1,  46.5,  48.5),
    _CountryBox('IQ', 29.0,  37.4,  38.8,  48.8),
    _CountryBox('IR', 25.0,  39.8,  44.0,  63.3),
    _CountryBox('IL', 29.5,  33.4,  34.3,  35.9),
    _CountryBox('LB', 33.1,  34.7,  35.1,  36.7),
    _CountryBox('TR', 35.8,  42.2,  26.0,  44.8),

    // Europe
    _CountryBox('GB', 49.9,  60.9,  -8.7,   1.8),
    _CountryBox('IE', 51.4,  55.4, -10.7,  -5.9),
    _CountryBox('FR', 41.3,  51.1,  -5.2,   9.6),
    _CountryBox('DE', 47.3,  55.1,   5.9,  15.1),
    _CountryBox('AT', 46.4,  49.1,   9.5,  17.2),
    _CountryBox('CH', 45.8,  47.8,   5.9,  10.5),
    _CountryBox('IT', 35.5,  47.1,   6.6,  18.5),
    _CountryBox('ES', 35.2,  43.8,  -9.4,   4.3),
    _CountryBox('PT', 36.9,  42.2,  -9.5,  -6.2),
    _CountryBox('NL', 50.7,  53.6,   3.3,   7.2),
    _CountryBox('BE', 49.5,  51.5,   2.5,   6.4),
    _CountryBox('SE', 55.3,  69.1,  11.0,  24.2),
    _CountryBox('NO', 58.0,  71.2,   4.6,  31.1),
    _CountryBox('FI', 59.8,  70.1,  20.5,  31.6),
    _CountryBox('DK', 54.5,  57.8,   8.0,  12.8),
    _CountryBox('PL', 49.0,  54.9,  14.1,  24.2),
    _CountryBox('CZ', 48.5,  51.1,  12.1,  18.9),
    _CountryBox('GR', 34.8,  41.8,  19.3,  28.3),
    _CountryBox('RU', 41.2,  78.0,  19.6, 180.0),
    _CountryBox('UA', 44.3,  52.4,  22.1,  40.2),

    // North America
    _CountryBox('US', 24.4,  49.4,-125.0, -66.9),
    _CountryBox('CA', 41.7,  83.2,-141.0, -52.6),
    _CountryBox('MX', 14.5,  32.7,-118.4, -86.7),

    // Latin America
    _CountryBox('BR',-33.8,   5.3, -74.0, -34.8),
    _CountryBox('AR',-55.1, -21.8, -73.6, -53.6),
    _CountryBox('CL',-55.8, -17.5, -75.7, -66.4),
    _CountryBox('CO', -4.2,  12.5, -79.0, -66.9),
    _CountryBox('PE',-18.4,  -0.0, -81.3, -68.7),
    _CountryBox('VE',  0.7,  12.2, -73.4, -59.8),

    // Oceania
    _CountryBox('AU',-43.7, -10.7, 112.9, 153.7),
    _CountryBox('NZ',-47.3, -34.1, 166.5, 178.6),

    // Africa
    _CountryBox('ZA',-34.9, -22.1,  16.4,  32.9),
    _CountryBox('NG',  4.2,  13.9,   2.7,  14.7),
    _CountryBox('KE', -4.7,   5.0,  33.9,  41.9),
    _CountryBox('ET',  3.4,  14.9,  33.0,  48.0),
    _CountryBox('MA', 27.6,  35.9, -13.2,  -1.0),
    _CountryBox('DZ', 19.0,  37.1,  -8.7,  12.0),
    _CountryBox('TN', 30.2,  37.5,   7.5,  11.6),
  ];
}
