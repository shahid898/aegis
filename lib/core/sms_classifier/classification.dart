import 'package:equatable/equatable.dart';

import '../alert/alert_event.dart';

enum AlertHazard {
  tsunami,
  earthquake,
  cyclone,
  flood,
  wildfire,
  evacuation,
  amberAlert,
  hazmat,
  terror,
  civilEmergency,
  unknown,
}

/// Decoupled severity vocabulary used by the classifier so that the platform
/// `AlertSeverity` enum can stay aligned with what the wire format ships.
enum AlertCategorySeverity { critical, high, medium, low }

extension AlertCategorySeverityX on AlertCategorySeverity {
  AlertSeverity toAlertSeverity() => switch (this) {
    AlertCategorySeverity.critical => AlertSeverity.critical,
    AlertCategorySeverity.high => AlertSeverity.high,
    AlertCategorySeverity.medium => AlertSeverity.medium,
    AlertCategorySeverity.low => AlertSeverity.low,
  };
}

class AlertClassification extends Equatable {
  const AlertClassification({
    required this.hazard,
    required this.severity,
    required this.confidence,
    required this.matchedTerms,
    required this.senderTrusted,
  });

  final AlertHazard hazard;
  final AlertCategorySeverity severity;
  final double confidence;
  final List<String> matchedTerms;
  final bool senderTrusted;

  bool get shouldWake =>
      hazard != AlertHazard.unknown ||
      senderTrusted ||
      severity == AlertCategorySeverity.critical;

  @override
  List<Object?> get props => [
    hazard,
    severity,
    confidence,
    matchedTerms,
    senderTrusted,
  ];

  static const AlertClassification unknown = AlertClassification(
    hazard: AlertHazard.unknown,
    severity: AlertCategorySeverity.low,
    confidence: 0,
    matchedTerms: <String>[],
    senderTrusted: false,
  );
}
