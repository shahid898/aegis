import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'alert_event.dart';

/// Flutter-side wrapper around the `com.resq.aegis/alert` MethodChannel.
///
/// Owns:
///  - the broadcast stream Flutter widgets/cubits subscribe to
///  - the cold-start recovery handshake (`getPendingAlert`)
///  - the simulator entry point used by debug screens and onboarding QA
///
/// All public methods short-circuit on non-Android platforms so iOS / desktop
/// don't blow up during development. Phase 5 will introduce mesh-side hooks
/// that call [deliver] directly without the platform channel.
class AlertBridge {
  AlertBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const String _channelName = 'com.resq.aegis/alert';
  static const String _methodDeliver = 'deliverAlert';
  static const String _methodDismiss = 'dismiss';
  static const String _methodSimulate = 'simulate';
  static const String _methodGetPending = 'getPendingAlert';
  static const String _methodEscalate = 'escalate';
  static const String _methodDismissPending = 'dismissPending';
  static const String _methodMoveToBack = 'moveToBack';

  final MethodChannel _channel;
  final StreamController<AlertEvent> _controller =
      StreamController<AlertEvent>.broadcast();

  AlertEvent? _latest;

  /// Stream of alerts pushed from the native layer (real SMS, simulations, mesh).
  Stream<AlertEvent> get alerts => _controller.stream;

  /// The most recent alert seen by this bridge, or `null` if none yet.
  AlertEvent? get latest => _latest;

  /// Pull any alert that was active when the engine cold-started. Safe to call
  /// repeatedly; a delivered alert will also surface through [alerts].
  Future<AlertEvent?> hydratePending() async {
    if (!_isSupported) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>?>(
        _methodGetPending,
      );
      final event = AlertEvent.fromMap(result);
      if (event != null) deliver(event);
      return event;
    } on PlatformException catch (e, st) {
      debugPrint('[AlertBridge] hydratePending failed: $e\n$st');
      return null;
    }
  }

  /// Inject a synthetic alert through the native pipeline. Useful for
  /// onboarding "wake the phone" demos without a real telco.
  Future<AlertEvent?> simulate({
    required String body,
    String? sender,
    AlertSeverity severity = AlertSeverity.critical,
  }) async {
    if (!_isSupported) return null;
    final args = <String, dynamic>{
      'body': body,
      if (sender != null) 'sender': sender,
      'severity': AlertEvent(
        id: '',
        source: AlertSource.simulation,
        body: body,
        receivedAt: DateTime.now(),
        severity: severity,
      ).toMap()['severity'],
    };
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>?>(
        _methodSimulate,
        args,
      );
      return AlertEvent.fromMap(res);
    } on PlatformException catch (e, st) {
      debugPrint('[AlertBridge] simulate failed: $e\n$st');
      return null;
    }
  }

  /// Tear down the active alert (foreground service + notification + ringer).
  Future<void> dismiss() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<bool>(_methodDismiss);
    } on PlatformException catch (e) {
      debugPrint('[AlertBridge] dismiss failed: $e');
    }
  }

  /// FunctionGemma verdict → upgrade [alertId] from PENDING to CONFIRMED.
  /// The Kotlin service ignores the call if [alertId] does not match the
  /// currently-pending alert (defends against stale Dart-side decisions
  /// racing a fresh inbound SMS).
  Future<void> escalate(String alertId) async {
    if (!_isSupported || alertId.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>(_methodEscalate, alertId);
    } on PlatformException catch (e) {
      debugPrint('[AlertBridge] escalate failed: $e');
    }
  }

  /// FunctionGemma verdict → tear down a PENDING alert that the LLM
  /// classified as a non-emergency. Distinct from [dismiss] only at the
  /// log level; the cleanup path is the same.
  Future<void> dismissPending(String alertId) async {
    if (!_isSupported || alertId.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>(_methodDismissPending, alertId);
    } on PlatformException catch (e) {
      debugPrint('[AlertBridge] dismissPending failed: $e');
    }
  }

  /// Push the host Activity to the back of the task stack — equivalent to
  /// the user pressing the Home key. The Dart isolate, foreground service,
  /// and any in-flight LLM verdict keep running; only the Flutter renderer
  /// stops drawing, which frees the GPU for Gemma's prefill + decode pass.
  /// The full-screen-intent re-foregrounds the app the moment the verdict
  /// says EMERGENCY.
  Future<void> moveToBack() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<bool>(_methodMoveToBack);
    } on PlatformException catch (e) {
      debugPrint('[AlertBridge] moveToBack failed: $e');
    }
  }

  /// Internal: surface a Dart-side alert into the broadcast stream. Called by
  /// the MethodChannel handler and by mesh ingestion in later sprints.
  void deliver(AlertEvent event) {
    _latest = event;
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case _methodDeliver:
        final raw = call.arguments;
        if (raw is Map) {
          final event = AlertEvent.fromMap(raw);
          if (event != null) deliver(event);
        }
        return true;
      default:
        return null;
    }
  }

  bool get _isSupported => defaultTargetPlatform == TargetPlatform.android;

  Future<void> close() async {
    _channel.setMethodCallHandler(null);
    await _controller.close();
  }
}
