import 'package:equatable/equatable.dart';

/// Wire format mirroring `com.resq.aegis.alert.AlertEvent` on the Kotlin side.
///
/// Construction is total-immutable; copy fields you want to override via
/// [copyWith]. The MethodChannel only ever ships JSON-safe primitives so we
/// keep this class free of platform types.
enum AlertSeverity { critical, high, medium, low, unknown }

enum AlertSource {
  sms,
  cellBroadcast,
  simulation,
  mesh,
  unknown,
}

/// PENDING → silent triage notification, no siren yet.
/// CONFIRMED → full lock-screen takeover, siren, vibration.
///
/// The foreground service starts every alert in [pending] and only
/// transitions to [confirmed] when FunctionGemma (or the watchdog
/// fallback) decides it's a real emergency.
enum AlertState { pending, confirmed }

class AlertEvent extends Equatable {
  const AlertEvent({
    required this.id,
    required this.source,
    required this.body,
    required this.receivedAt,
    required this.severity,
    this.sender,
    this.state = AlertState.pending,
  });

  final String id;
  final AlertSource source;
  final String? sender;
  final String body;
  final DateTime receivedAt;
  final AlertSeverity severity;
  final AlertState state;

  AlertEvent copyWith({
    String? id,
    AlertSource? source,
    String? sender,
    String? body,
    DateTime? receivedAt,
    AlertSeverity? severity,
    AlertState? state,
  }) {
    return AlertEvent(
      id: id ?? this.id,
      source: source ?? this.source,
      sender: sender ?? this.sender,
      body: body ?? this.body,
      receivedAt: receivedAt ?? this.receivedAt,
      severity: severity ?? this.severity,
      state: state ?? this.state,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'source': _sourceToWire(source),
    'sender': sender,
    'body': body,
    'receivedAtEpochMs': receivedAt.millisecondsSinceEpoch,
    'severity': _severityToWire(severity),
    'state': _stateToWire(state),
  };

  static AlertEvent? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final id = map['id'];
    final body = map['body'];
    if (id is! String || body is! String) return null;

    final epoch = map['receivedAtEpochMs'];
    final receivedAt = epoch is int
        ? DateTime.fromMillisecondsSinceEpoch(epoch)
        : DateTime.now();

    return AlertEvent(
      id: id,
      source: _sourceFromWire(map['source']),
      sender: map['sender'] as String?,
      body: body,
      receivedAt: receivedAt,
      severity: _severityFromWire(map['severity']),
      state: _stateFromWire(map['state']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    source,
    sender,
    body,
    receivedAt,
    severity,
    state,
  ];

  static String _sourceToWire(AlertSource s) => switch (s) {
    AlertSource.sms => 'sms',
    AlertSource.cellBroadcast => 'cell_broadcast',
    AlertSource.simulation => 'simulation',
    AlertSource.mesh => 'mesh',
    AlertSource.unknown => 'unknown',
  };

  static AlertSource _sourceFromWire(Object? v) => switch (v) {
    'sms' => AlertSource.sms,
    'cell_broadcast' => AlertSource.cellBroadcast,
    'simulation' => AlertSource.simulation,
    'mesh' => AlertSource.mesh,
    _ => AlertSource.unknown,
  };

  static String _severityToWire(AlertSeverity s) => switch (s) {
    AlertSeverity.critical => 'critical',
    AlertSeverity.high => 'high',
    AlertSeverity.medium => 'medium',
    AlertSeverity.low => 'low',
    AlertSeverity.unknown => 'unknown',
  };

  static AlertSeverity _severityFromWire(Object? v) => switch (v) {
    'critical' => AlertSeverity.critical,
    'high' => AlertSeverity.high,
    'medium' => AlertSeverity.medium,
    'low' => AlertSeverity.low,
    _ => AlertSeverity.unknown,
  };

  static String _stateToWire(AlertState s) => switch (s) {
    AlertState.pending => 'pending',
    AlertState.confirmed => 'confirmed',
  };

  static AlertState _stateFromWire(Object? v) => switch (v) {
    'confirmed' => AlertState.confirmed,
    _ => AlertState.pending,
  };
}
