import 'dart:async';

import 'package:flutter/foundation.dart';

/// One briefing pushed by the alert pipeline into the in-app surface.
///
/// Emitted by [SummarizeForUserHandler] when the model decides the user
/// should hear a summary of the inbound alert. The assistant cubit
/// listens to [AlertBriefingSink.stream] and renders each event as a
/// synthetic conversation turn so the user can read the briefing on the
/// home screen, not just hear it.
@immutable
class AlertBriefing {
  const AlertBriefing({
    required this.alertId,
    required this.severity,
    required this.briefing,
    required this.languageCode,
  });

  /// The id of the inbound alert that triggered the briefing — handy
  /// for de-duplication if the cubit re-attaches mid-flight.
  final String alertId;

  /// Severity level the router classified ("critical" / "high" /
  /// "medium" / "low"). The UI may colour the bubble accordingly.
  final String severity;

  /// 2–3 sentence summary the model generated. Already in the user's
  /// preferred language (the verdict prompt forces translation).
  final String briefing;

  /// ISO-639 code the briefing is written in. Null when the user has
  /// not picked a language during onboarding.
  final String? languageCode;
}

/// Pub/sub seam between [SummarizeForUserHandler] (publisher) and the
/// in-app assistant surface (subscriber). Held as a singleton in the DI
/// container so handlers and cubits can hook in without mutual imports.
///
/// Uses a broadcast stream for live delivery to any in-flight cubit, and
/// caches the most recent briefing as [pending] for cold-launch replay
/// — when an alert arrives while the app is closed, the briefing is
/// produced and stashed *before* the auto-launch surfaces the home
/// screen. The newly-mounted assistant cubit reads [pending] on
/// subscribe and calls [consumePending] so the TTS + chat-bubble
/// surface fires exactly once (not at handler time, when the user is
/// still staring at the takeover screen with the siren going).
class AlertBriefingSink {
  AlertBriefingSink();

  final StreamController<AlertBriefing> _controller =
      StreamController<AlertBriefing>.broadcast();

  AlertBriefing? _pending;

  Stream<AlertBriefing> get stream => _controller.stream;

  /// Last briefing pushed by the alert pipeline that no in-app surface
  /// has consumed yet. Null after [consumePending] or when nothing has
  /// fired this session.
  AlertBriefing? get pending => _pending;

  void publish(AlertBriefing briefing) {
    if (_controller.isClosed) return;
    _pending = briefing;
    _controller.add(briefing);
  }

  /// Mark the cached pending briefing as consumed by an in-app surface
  /// so subsequent subscribers don't replay it. Idempotent.
  void consumePending() {
    _pending = null;
  }

  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
