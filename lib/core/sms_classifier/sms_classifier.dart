import '../alert/alert_event.dart';
import 'classification.dart';

/// Pass-through "classifier" kept only as a structural seam between the
/// bridge and the FunctionGemma router.
///
/// Aegis used to run a regex first-pass here that tagged each inbound SMS
/// with a hazard category, severity, and trusted-sender flag. That
/// approach turned the regex into the real arbiter on every cold-start
/// alert (because the LLM watchdog timed out before FunctionGemma
/// produced a token), which let promo SMS tagged with "EMERGENCY SALE"
/// trip the siren and made the on-device LLM cosmetic.
///
/// The new policy: **FunctionGemma is the sole arbiter**. The router
/// receives the raw body + sender and decides. We keep the
/// [AlertClassification] type only so the function-router signature
/// doesn't need to change everywhere; every field is the "I don't
/// know" value (`unknown`, `low`, `0.0`, empty matches, untrusted),
/// which the router prompt now ignores entirely.
class SmsClassifier {
  const SmsClassifier();

  AlertClassification classify({
    required String body,
    String? sender,
  }) {
    // Intentionally no regex, no allow-list, no severity heuristic.
    // The downstream FunctionRouter and AlertRouter both treat the
    // classification as opaque metadata now and judge purely on body+sender.
    return AlertClassification.unknown;
  }

  /// Convenience: stamp a classification onto an [AlertEvent]'s severity.
  /// With the pass-through classifier the resulting severity is always
  /// [AlertSeverity.low] — kept for callers that want a "no-info" stamp.
  AlertEvent annotate(AlertEvent event, AlertClassification classification) {
    return event.copyWith(severity: classification.severity.toAlertSeverity());
  }
}
