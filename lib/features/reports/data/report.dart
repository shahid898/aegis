import 'package:flutter/foundation.dart';

/// One confirmed triage report. Persisted as JSON in a Hive
/// `Box<String>`, replayed on demand into a fresh
/// [genui.SurfaceController] so the historical card renders identical
/// to the moment it was confirmed.
///
/// We store the raw LLM stream output ([rawLlmOutput]) instead of a
/// pre-parsed surface definition because:
///   * It round-trips exactly through `A2uiParserTransformer` —
///     no shape drift if genui changes its internal model.
///   * It's a single string field, easy to migrate.
///   * It captures the spoken prose alongside the JSON envelopes,
///     so a future "summary view" can show the full context.
@immutable
class Report {
  const Report({
    required this.id,
    required this.userText,
    required this.assistantText,
    required this.createdAt,
    required this.rawLlmOutput,
    this.gpsContext,
  });

  /// Unique id — also the Hive key. We use ISO timestamps as ids so
  /// the natural lexicographic order of Hive's `keys` matches
  /// chronological order; the Reports page displays newest-first by
  /// reversing the list.
  final String id;

  /// Verbatim user message that triggered this report (typically what
  /// they typed in the triage intake card, plus any captured audio /
  /// image references in a future revision).
  final String userText;

  /// The assistant's natural-language reply alongside the surface —
  /// useful as a one-line summary in the reports list.
  final String assistantText;

  /// Wall-clock time at confirmation. Drives the list ordering and is
  /// shown to the user in the report detail header.
  final DateTime createdAt;

  /// Raw LLM stream output captured for this turn, including JSON
  /// envelopes and prose. Replayed via [genui.A2uiParserTransformer]
  /// when rendering the report detail page.
  final String rawLlmOutput;

  /// Optional GPS line snapshotted at capture time. Null on devices
  /// without permission; when set, surfaced as a one-line subtitle.
  final String? gpsContext;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'userText': userText,
        'assistantText': assistantText,
        'createdAt': createdAt.toIso8601String(),
        'rawLlmOutput': rawLlmOutput,
        if (gpsContext != null) 'gpsContext': gpsContext,
      };

  factory Report.fromJson(Map<String, Object?> json) {
    return Report(
      id: json['id'] as String,
      userText: (json['userText'] as String?) ?? '',
      assistantText: (json['assistantText'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      rawLlmOutput: (json['rawLlmOutput'] as String?) ?? '',
      gpsContext: json['gpsContext'] as String?,
    );
  }
}
