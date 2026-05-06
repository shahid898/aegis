import 'dart:async';

import 'package:flutter/foundation.dart';

import '../llm/function_call.dart';
import '../llm/function_router.dart';
import '../sms_classifier/classification.dart';
import '../sms_classifier/sms_classifier.dart';
import '../storage/storage_service.dart';
import '../voice/tts_service.dart';
import 'alert_bridge.dart';
import 'alert_event.dart';
import 'alert_handler.dart';

/// Top-level coordinator for inbound emergency alerts.
///
/// Pipeline:
///
/// ```
///   AlertBridge.alerts (Kotlin → Flutter)
///        │  (alert arrives in PENDING state — silent heads-up only)
///        ▼
///   SmsClassifier.classify          (no-op pass-through — see file doc)
///        │
///        ▼  (Dart watchdog armed: [_dartWatchdog])
///   FunctionRouter.route            (FunctionGemma → function calls)
///        │
///        ▼
///   ┌────────────────────────────────────────────────┐
///   │ if plan contains dispatch_local_alarm:         │
///   │   → bridge.escalate(id) → service goes loud    │
///   │ else (no actionable call):                     │
///   │   → bridge.dismissPending(id) → silent teardown│
///   └────────────────────────────────────────────────┘
///        │
///        ▼
///   AlertHandler dispatch table     (per-action side effects)
/// ```
///
/// **FunctionGemma is the sole arbiter.** There is no regex hazard
/// classifier or trusted-sender allow-list any more — the router gives
/// FunctionGemma the raw body + sender and trusts its verdict. If the
/// LLM times out, errors out, or returns no parseable plan, the
/// PENDING heads-up is dismissed (the user has already seen the silent
/// notification, so we don't go from silence to a siren without an
/// LLM-blessed reason to). The native side runs an even-longer
/// watchdog as a last-resort safety net for a dead Flutter engine, and
/// that watchdog also defaults to dismiss for the same reason.
///
/// CONFIRMED-state re-deliveries (the service pushing the same event back
/// up after `notifyDelivered`) are short-circuited — the routing
/// decision was already made when the event was PENDING.
class AlertRouter {
  AlertRouter({
    required AlertBridge bridge,
    required SmsClassifier classifier,
    required FunctionRouter functionRouter,
    required TtsService tts,
    required StorageService storage,
    Map<FunctionRouteAction, AlertHandler>? handlers,
    String Function()? preferredLanguage,
    // 90 s budget covers a fully-cold Gemma 4 IT decode: shader compile
    // (~10–15 s on first GPU dispatch) + KV-cache prefill of the verdict
    // prompt (~10–20 s for ~600 prompt tokens) + 20 s of decode for the
    // VERDICT/SEVERITY/REASON/ACTIONS/BRIEFING/CONTACT_MESSAGE envelope.
    // The boot-time [LlmService.warmUp] now does a 1-token decode to pay
    // the shader-compile cost ahead of the first alert, so warm calls
    // land at ~3–6 s. The native-side watchdog [LLM_VERDICT_TIMEOUT_MS]
    // is set wider still so this Dart watchdog always fires first when
    // both are armed.
    Duration dartWatchdog = const Duration(seconds: 90),
  }) : _bridge = bridge,
       _classifier = classifier,
       _functionRouter = functionRouter,
       _tts = tts,
       _storage = storage,
       _handlers = handlers ?? defaultAlertHandlers(),
       _preferredLanguage = preferredLanguage,
       _dartWatchdog = dartWatchdog;

  final AlertBridge _bridge;
  final SmsClassifier _classifier;
  final FunctionRouter _functionRouter;
  final TtsService _tts;
  final StorageService _storage;
  final Map<FunctionRouteAction, AlertHandler> _handlers;
  final String Function()? _preferredLanguage;
  final Duration _dartWatchdog;

  StreamSubscription<AlertEvent>? _subscription;
  bool _started = false;
  final Set<String> _routed = <String>{};

  /// Begin listening to [AlertBridge.alerts]. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _subscription = _bridge.alerts.listen(
      _onAlert,
      onError: (Object e, StackTrace st) {
        if (kDebugMode) debugPrint('[AlertRouter] bridge error: $e\n$st');
      },
    );
    if (kDebugMode) debugPrint('[AlertRouter] subscribed to AlertBridge');
  }

  Future<void> stop() async {
    _started = false;
    await _subscription?.cancel();
    _subscription = null;
    _routed.clear();
  }

  Future<void> _onAlert(AlertEvent event) async {
    // CONFIRMED re-deliveries from the service are status updates, not
    // new routing inputs. The original PENDING delivery already made the
    // verdict — don't re-run FunctionGemma on it.
    if (event.state == AlertState.confirmed) {
      if (kDebugMode) {
        debugPrint(
          '[AlertRouter] ignoring CONFIRMED re-delivery id=${event.id}',
        );
      }
      return;
    }

    // Defend against duplicate PENDING deliveries (e.g. cold-start
    // hydratePending firing right after the live broadcast).
    if (!_routed.add(event.id)) {
      if (kDebugMode) {
        debugPrint('[AlertRouter] skipping duplicate id=${event.id}');
      }
      return;
    }

    // Pass-through classifier; kept in the call chain only so the
    // function router signature stays stable. Every field is "unknown"
    // and the router prompt no longer reads them.
    final classification = _classifier.classify(
      body: event.body,
      sender: event.sender,
    );
    if (kDebugMode) {
      debugPrint('[AlertRouter] alert id=${event.id} → asking FunctionGemma');
    }

    final calls = await _planCallsWithWatchdog(event, classification);
    final ctx = AlertContext(
      event: event,
      bridge: _bridge,
      tts: _tts,
      storage: _storage,
    );

    // Drive the PENDING → CONFIRMED state machine *before* running the
    // side-effecting handlers so the user-facing siren transition kicks
    // off as soon as the verdict is in.
    await _applyVerdict(event, calls);

    for (final call in calls) {
      await _safeDispatch(call, ctx);
    }
  }

  /// Race the FunctionRouter against [_dartWatchdog]. With the regex
  /// fallback gone, a timeout / error / empty-plan all collapse to the
  /// same outcome: an empty list of calls, which [_applyVerdict] will
  /// translate to `dismissPending`. The siren stays silent unless
  /// FunctionGemma explicitly emits `dispatch_local_alarm`.
  Future<List<FunctionCall>> _planCallsWithWatchdog(
    AlertEvent event,
    AlertClassification classification,
  ) async {
    final lang = _preferredLanguage?.call();
    try {
      final routed = await _functionRouter
          .route(
            event: event,
            classification: classification,
            preferredLanguage: lang,
          )
          .timeout(_dartWatchdog);
      return routed;
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint(
          '[AlertRouter] FunctionGemma watchdog (${_dartWatchdog.inSeconds}s) '
          'fired for id=${event.id} — defaulting to DISMISS',
        );
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[AlertRouter] FunctionGemma threw for id=${event.id}: $e\n$st',
        );
      }
    }
    return const [];
  }

  /// Translate the parsed plan into a single state-machine transition on
  /// the native foreground service:
  ///
  ///  * any `dispatch_local_alarm` → escalate (siren on)
  ///  * everything else (including empty plan) → dismissPending
  ///
  /// Idempotent on the native side: the service ignores escalate /
  /// dismissPending intents whose id doesn't match the currently-pending
  /// alert.
  Future<void> _applyVerdict(AlertEvent event, List<FunctionCall> calls) async {
    final shouldEscalate = calls.any(
      (c) => c.action == FunctionRouteAction.dispatchLocalAlarm,
    );
    if (shouldEscalate) {
      if (kDebugMode) {
        debugPrint('[AlertRouter] verdict=ESCALATE id=${event.id}');
      }
      await _bridge.escalate(event.id);
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[AlertRouter] verdict=DISMISS id=${event.id} '
        '(plan=${calls.map((c) => c.action.wireName).join(",")})',
      );
    }
    await _bridge.dismissPending(event.id);
  }

  Future<void> _safeDispatch(FunctionCall call, AlertContext ctx) async {
    final handler = _handlers[call.action];
    if (handler == null) {
      if (kDebugMode) {
        debugPrint(
          '[AlertRouter] no handler registered for ${call.action.wireName}, '
          'skipping',
        );
      }
      return;
    }
    try {
      await handler.handle(call, ctx);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[AlertRouter] handler ${call.action.wireName} threw: $e\n$st',
        );
      }
    }
  }
}
