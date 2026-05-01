import 'classification.dart';

/// One hazard label with the regex hints that surface it.
///
/// Public so the analyzer doesn't complain about the catalogue's element type
/// leaking into a public API; the constructor is `const` and the patterns are
/// immutable, so consumers can read but not mutate.
class HazardPattern {
  const HazardPattern({
    required this.hazard,
    required this.severity,
    required this.patterns,
  });

  final AlertHazard hazard;
  final AlertCategorySeverity severity;
  final List<RegExp> patterns;

  bool matches(String body) => patterns.any((p) => p.hasMatch(body));
}

/// Hand-curated catalogue of regex hints we look for in WEA / CAP-style SMS.
///
/// Sprint 4 will swap this out for FunctionGemma-driven structured extraction;
/// until then the regexes are good enough to drive the wake path with very
/// low false-negative rate. Patterns are intentionally permissive — Whisper /
/// the briefing model will refine the language; here we only need a label.
class WeaPatterns {
  const WeaPatterns._();

  static final List<HazardPattern> hazards = [
    HazardPattern(
      hazard: AlertHazard.tsunami,
      severity: AlertCategorySeverity.critical,
      patterns: [
        RegExp(r'\btsunami\b', caseSensitive: false),
        RegExp(r'सुनामी'),
        RegExp(r'สึนามิ'),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.earthquake,
      severity: AlertCategorySeverity.critical,
      patterns: [
        RegExp(r'\bearthquake\b', caseSensitive: false),
        RegExp(r'\bquake\b', caseSensitive: false),
        RegExp(r'भूकंप'),
        RegExp(r'แผ่นดินไหว'),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.cyclone,
      severity: AlertCategorySeverity.critical,
      patterns: [
        RegExp(r'\bcyclone\b', caseSensitive: false),
        RegExp(r'\bhurricane\b', caseSensitive: false),
        RegExp(r'\btyphoon\b', caseSensitive: false),
        RegExp(r'चक्रवात'),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.flood,
      severity: AlertCategorySeverity.high,
      patterns: [
        RegExp(r'\bflood', caseSensitive: false),
        RegExp(r'\bflash[\s-]?flood', caseSensitive: false),
        RegExp(r'बाढ़'),
        RegExp(r'น้ำท่วม'),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.wildfire,
      severity: AlertCategorySeverity.high,
      patterns: [
        RegExp(r'\bwildfire\b', caseSensitive: false),
        RegExp(r'\bbushfire\b', caseSensitive: false),
        RegExp(r'\bforest fire\b', caseSensitive: false),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.evacuation,
      severity: AlertCategorySeverity.critical,
      patterns: [
        RegExp(r'\bevacuat', caseSensitive: false),
        RegExp(r'\bshelter[\s-]in[\s-]place\b', caseSensitive: false),
        RegExp(r'खाली कर'),
        RegExp(r'อพยพ'),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.amberAlert,
      severity: AlertCategorySeverity.high,
      patterns: [
        RegExp(r'\bamber alert\b', caseSensitive: false),
        RegExp(r'\bchild abduction\b', caseSensitive: false),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.hazmat,
      severity: AlertCategorySeverity.high,
      patterns: [
        RegExp(r'\bhazmat\b', caseSensitive: false),
        RegExp(r'\bchemical (spill|leak|release)\b', caseSensitive: false),
        RegExp(r'\bgas leak\b', caseSensitive: false),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.terror,
      severity: AlertCategorySeverity.critical,
      patterns: [
        RegExp(r'\bterror', caseSensitive: false),
        RegExp(r'\bactive shooter\b', caseSensitive: false),
        RegExp(r'\bbomb threat\b', caseSensitive: false),
      ],
    ),
    HazardPattern(
      hazard: AlertHazard.civilEmergency,
      severity: AlertCategorySeverity.medium,
      patterns: [
        RegExp(r'\bcivil emergency\b', caseSensitive: false),
        RegExp(r'\bemergency alert\b', caseSensitive: false),
        RegExp(r'आपातकाल'),
      ],
    ),
  ];

  /// Trusted government / telco short-codes. Match → boost severity floor.
  static final List<RegExp> trustedSenders = [
    RegExp(r'^(VK|VM|VD|JD|JK|JM|JX)-?\w+$'), // Indian telco short-codes
    RegExp(r'^IMD\b', caseSensitive: false),
    RegExp(r'^NDMA\b', caseSensitive: false),
    RegExp(r'^WEA\b', caseSensitive: false),
    RegExp(r'^FEMA\b', caseSensitive: false),
    RegExp(r'^CMAS\b', caseSensitive: false),
    RegExp(r'^GOV', caseSensitive: false),
  ];

  /// Generic emergency hint regex used as a last-resort wake signal when no
  /// specific hazard matches but the body smells like an alert.
  static final RegExp emergencyHint = RegExp(
    r'\b(emergency|urgent|warning|danger|alert|evacuat|shelter)\b',
    caseSensitive: false,
  );
}
