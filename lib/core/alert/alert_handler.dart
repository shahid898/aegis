import 'package:flutter/foundation.dart';

import '../llm/function_call.dart';
import 'alert_bridge.dart';
import 'alert_event.dart';

/// Side-effecting context an [AlertHandler] needs to do its job. We keep
/// this as a struct (rather than passing all five things to every
/// handler) so adding a new collaborator (e.g. mesh transport in Sprint 5)
/// doesn't require touching every handler signature.
class AlertContext {
  const AlertContext({
    required this.event,
    required this.bridge,
  });

  /// The alert that triggered the route.
  final AlertEvent event;

  /// The platform bridge — handlers use it to dismiss the foreground
  /// service or push synthetic events back into the stream.
  final AlertBridge bridge;
}

/// Single-method strategy. Implementations only run for the action they
/// register against in [AlertRouter]'s handler map.
abstract class AlertHandler {
  Future<void> handle(FunctionCall call, AlertContext ctx);
}

/// Re-arms the local siren. The actual ringer lives in
/// `AlertForegroundService` on the Kotlin side; this handler is mostly a
/// nicety because the service is started by the SMS receiver before
/// Flutter even wakes up. We log so QA can verify the routing path.
class DispatchLocalAlarmHandler implements AlertHandler {
  const DispatchLocalAlarmHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final severity = call.arguments['severity'];
    final reason = call.arguments['reason'];
    if (kDebugMode) {
      debugPrint(
        '[AlertHandler] dispatch_local_alarm severity=$severity '
        'reason="$reason" alertId=${ctx.event.id}',
      );
    }
    // Sprint 2 stub: native foreground service is already up. Sprint 4
    // will broadcast a status event to the in-app cubit so the takeover
    // screen can render the model's `reason` label live.
  }
}

/// Briefing handler stub. Sprint 3 will pipe `briefing` into TTS so the
/// app reads the summary aloud while the lock-screen takeover is up.
class SummarizeForUserHandler implements AlertHandler {
  const SummarizeForUserHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final lang = call.arguments['language'];
    final briefing = call.arguments['briefing'];
    if (kDebugMode) {
      debugPrint(
        '[AlertHandler] summarize_for_user lang=$lang '
        'briefing="$briefing"',
      );
    }
  }
}

/// Notify-contacts stub. Sprint 4 will share the message via SMS / system
/// share-sheet using `url_launcher` (already in pubspec).
class NotifyEmergencyContactsHandler implements AlertHandler {
  const NotifyEmergencyContactsHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final message = call.arguments['message'];
    if (kDebugMode) {
      debugPrint(
        '[AlertHandler] notify_emergency_contacts message="$message"',
      );
    }
  }
}

/// Mesh-relay stub. Sprint 5 will hand the payload to the BLE mesh layer
/// once the wire format and TTL semantics are nailed down.
class ActivateMeshRelayHandler implements AlertHandler {
  const ActivateMeshRelayHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final ttl = call.arguments['ttl_minutes'];
    if (kDebugMode) {
      debugPrint('[AlertHandler] activate_mesh_relay ttl=$ttl');
    }
  }
}

/// Fallback handler when the router was uncertain. We keep the takeover
/// screen visible so the user can read the raw text and decide.
class RequestClarificationHandler implements AlertHandler {
  const RequestClarificationHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final reason = call.arguments['reason'];
    if (kDebugMode) {
      debugPrint(
        '[AlertHandler] request_clarification reason="$reason" '
        '(keeping takeover screen visible)',
      );
    }
  }
}

/// Convenience: the default handler map wired into [AlertRouter] when
/// callers don't supply their own. Tests can override individual entries
/// with fakes.
Map<FunctionRouteAction, AlertHandler> defaultAlertHandlers() {
  return const <FunctionRouteAction, AlertHandler>{
    FunctionRouteAction.dispatchLocalAlarm: DispatchLocalAlarmHandler(),
    FunctionRouteAction.summarizeForUser: SummarizeForUserHandler(),
    FunctionRouteAction.notifyEmergencyContacts:
        NotifyEmergencyContactsHandler(),
    FunctionRouteAction.activateMeshRelay: ActivateMeshRelayHandler(),
    FunctionRouteAction.requestClarification: RequestClarificationHandler(),
  };
}
