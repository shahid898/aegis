import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/voice/triage_report.dart';

/// One confirmed triage report. Persisted as JSON in a Hive
/// `Box<String>` and rendered by [TriageReportCard] when opened.
///
/// Stores the structured [TriageReport] payload (serialized as JSON
/// in [reportJson]) emitted by Gemma 4's `render_triage_report`
/// native tool call. Replaces the legacy `rawLlmOutput` field that
/// captured the streaming A2UI envelope — the new path has no stream
/// to capture; the model returns one [FunctionCallResponse].
@immutable
class Report {
  const Report({
    required this.id,
    required this.userText,
    required this.assistantText,
    required this.createdAt,
    required this.reportJson,
    this.gpsContext,
    this.imagePath,
    this.audioPath,
  });

  /// Unique id — also the Hive key. ISO timestamps so lexicographic
  /// order matches chronological order.
  final String id;

  /// Verbatim user message that triggered this report (intake text +
  /// any captured-evidence stub).
  final String userText;

  /// The assistant's spoken summary that played alongside the report
  /// card. Falls back to the report's `summary` when no spoken
  /// summary was emitted.
  final String assistantText;

  /// Wall-clock time at confirmation.
  final DateTime createdAt;

  /// [TriageReport] serialized as JSON. Decoded on demand via
  /// [report] so the reports list itself doesn't have to parse every
  /// stored payload.
  final String reportJson;

  /// GPS line snapshotted at capture time.
  final String? gpsContext;

  /// Absolute path on the app's documents directory to the JPEG.
  final String? imagePath;

  /// Absolute path to the WAV recorded during voice intake.
  final String? audioPath;

  /// Lazily decode [reportJson] into a [TriageReport]. Returns null
  /// when the payload is missing or malformed (legacy / corrupt
  /// records).
  TriageReport? get report {
    if (reportJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(reportJson);
      if (decoded is Map<String, Object?>) {
        return TriageReport.fromJson(decoded);
      }
      if (decoded is Map) {
        return TriageReport.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } on FormatException {
      // Drop malformed payloads — the reports list still renders
      // metadata; only the detail card is missing.
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'userText': userText,
        'assistantText': assistantText,
        'createdAt': createdAt.toIso8601String(),
        'reportJson': reportJson,
        if (gpsContext != null) 'gpsContext': gpsContext,
        if (imagePath != null) 'imagePath': imagePath,
        if (audioPath != null) 'audioPath': audioPath,
      };

  factory Report.fromJson(Map<String, Object?> json) {
    // Migration: pre-0.15 records stored A2UI stream output under
    // `rawLlmOutput`. We can't render that with the new pipeline, so
    // surface it as empty `reportJson` — the detail view falls back
    // to a "legacy report" placeholder.
    final structured = (json['reportJson'] as String?) ?? '';
    return Report(
      id: json['id'] as String,
      userText: (json['userText'] as String?) ?? '',
      assistantText: (json['assistantText'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      reportJson: structured,
      gpsContext: json['gpsContext'] as String?,
      imagePath: json['imagePath'] as String?,
      audioPath: json['audioPath'] as String?,
    );
  }
}
