import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../llm/function_call.dart';
import '../storage/storage_service.dart';
import '../voice/tts_service.dart';
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
    required this.tts,
    required this.storage,
  });

  /// The alert that triggered the route.
  final AlertEvent event;

  /// The platform bridge — handlers use it to dismiss the foreground
  /// service or push synthetic events back into the stream.
  final AlertBridge bridge;

  /// Voice surface used by [SummarizeForUserHandler] to read the model's
  /// briefing aloud while the takeover screen is visible.
  final TtsService tts;

  /// Persistent storage — [NotifyEmergencyContactsHandler] reads the
  /// user's saved contacts from here.
  final StorageService storage;
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
    // Native foreground service is already up via [AlertRouter._applyVerdict];
    // the actual siren transition happened there. This handler stays as
    // a logging seam so QA can correlate the verdict with the takeover
    // screen state.
  }
}

/// Reads the model's briefing aloud over the takeover screen via TTS.
///
/// Two sources for the spoken text, in order of preference:
///   1. `briefing` argument supplied by the router — Gemma 4 generated
///      a 2-3 sentence summary on the verdict pass.
///   2. The raw alert body (truncated). Last-resort fallback so the
///      user always hears *something* when summarize_for_user fires.
///
/// Speaking is fire-and-forget (`enqueue`) so the handler returns
/// immediately and the next handler in the dispatch chain (e.g.
/// notify_emergency_contacts) can run while audio plays.
class SummarizeForUserHandler implements AlertHandler {
  const SummarizeForUserHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final briefing = (call.arguments['briefing'] as String?)?.trim();
    final spoken =
        (briefing != null && briefing.isNotEmpty && briefing != 'NONE')
        ? briefing
        : _fallbackFromBody(ctx.event.body);
    if (spoken.isEmpty) {
      if (kDebugMode) {
        debugPrint('[AlertHandler] summarize_for_user: no text to speak');
      }
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[AlertHandler] summarize_for_user briefing="${_clip(spoken, 80)}"',
      );
    }
    try {
      await ctx.tts.enqueue(spoken);
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AlertHandler] TTS enqueue failed: $e\n$st');
      }
    }
  }

  String _fallbackFromBody(String body) {
    final cleaned = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 240) return cleaned;
    return '${cleaned.substring(0, 237)}...';
  }

  String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

/// Sends an SMS to every saved emergency contact via the platform's
/// messaging app (composed but not auto-sent — the user taps Send).
///
/// We use a `sms:?addresses=...&body=...` URI through [url_launcher]
/// rather than the SEND_SMS permission so the app doesn't need a
/// special carrier-billing permission and the user always confirms
/// before a message goes out. Multiple recipients are concatenated
/// with `,` which is the de-facto standard parsed by both the Android
/// Messages app and iOS Messages.
///
/// Two sources for the body, in order:
///   1. `message` argument supplied by the router (Gemma 4 wrote a
///      contact-facing line).
///   2. A canned template built from the alert's REASON / body.
class NotifyEmergencyContactsHandler implements AlertHandler {
  const NotifyEmergencyContactsHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final contacts = ctx.storage.emergencyContacts;
    if (contacts.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[AlertHandler] notify_emergency_contacts skipped — no saved contacts',
        );
      }
      return;
    }

    final raw = (call.arguments['message'] as String?)?.trim();
    final body = (raw != null && raw.isNotEmpty && raw != 'NONE')
        ? raw
        : _defaultBody(ctx.event);

    final recipients = contacts
        .map((c) => c.phone.trim())
        .where((p) => p.isNotEmpty);
    if (recipients.isEmpty) return;

    final uri = Uri(
      scheme: 'sms',
      // `;` works on iOS, `,` works on Android — pick `,` since this app
      // ships Android-first. iOS users will see the first recipient and
      // can add the rest manually.
      path: recipients.join(','),
      queryParameters: <String, String>{'body': body},
    );
    if (kDebugMode) {
      debugPrint(
        '[AlertHandler] notify_emergency_contacts recipients=${recipients.length} '
        'body="${_clip(body, 80)}"',
      );
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && kDebugMode) {
        debugPrint('[AlertHandler] launchUrl(sms:) returned false');
      }
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('[AlertHandler] launchUrl(sms:) threw: $e\n$st');
      }
    }
  }

  String _defaultBody(AlertEvent event) {
    final body = event.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final clipped = body.length <= 200 ? body : '${body.substring(0, 197)}...';
    return 'Aegis emergency alert: $clipped';
  }

  String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

/// Mesh-relay stub. Sprint 5 will hand the payload to the BLE mesh layer
/// once the wire format and TTL semantics are nailed down.
class ActivateMeshRelayHandler implements AlertHandler {
  const ActivateMeshRelayHandler();

  @override
  Future<void> handle(FunctionCall call, AlertContext ctx) async {
    final ttl = call.arguments['ttl_minutes'];
    if (kDebugMode) {
      debugPrint(
        '[AlertHandler] activate_mesh_relay ttl=$ttl '
        '(stub — BLE transport lands in Sprint 5)',
      );
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
