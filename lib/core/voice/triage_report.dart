import 'package:flutter/foundation.dart';

/// Structured triage analysis produced by Gemma 4 via the
/// `render_triage_report` native tool call (flutter_gemma 0.15.0,
/// `ModelType.gemma4`).
///
/// Replaces the streamed A2UI JSON tree. The report UI is fixed in
/// Flutter, so the model only emits the *analysis fields* it would
/// have filled into a card anyway — saving ~80% of decode tokens
/// compared to the old surface-tree pipeline.
@immutable
class TriageReport {
  const TriageReport({
    required this.format,
    required this.title,
    required this.severity,
    required this.summary,
    required this.body,
    required this.immediateActions,
    required this.preparedAt,
    required this.preparedBy,
    this.hazardType,
    this.hazusCategory,
    this.femaScale,
    this.damageDescription,
    this.casualtyStatus,
    this.casualtyCount,
    this.casualtyTriageColor,
    this.gps,
    this.recommendedSkill,
    this.spokenSummary,
  });

  /// Report template — `ICS-209`, `OCHA_SITREP`, `UN_FLASH_UPDATE`,
  /// `NDRRMC`, `IFRC_OPS_UPDATE`, `EU_ECHO_FLASH`, `PDNA`. Default
  /// `ICS-209` when ambiguous.
  final String format;

  /// One-line title (e.g. "Building Collapse Incident").
  final String title;

  /// Severity bucket — `CRITICAL` / `HIGH` / `MODERATE` / `LOW` /
  /// `INFO`. Drives the accent color and emergency-services call-out.
  final String severity;

  /// ≤180-char descriptive summary of the situation. Card subtitle.
  final String summary;

  /// Full filled report body in the picked [format] (~1–3 KB).
  /// Preserves newlines. Rendered by `IncidentReportBody`.
  final String body;

  /// Short imperative steps the responder should take *now*. Ordered.
  final List<String> immediateActions;

  /// ISO-8601 UTC timestamp from the user prompt's `Captured at:`
  /// line.
  final String preparedAt;

  /// Always `"Aegis Triage Auto-Draft"`. Responder edits at confirm.
  final String preparedBy;

  /// `STRUCTURAL_DAMAGE` / `CASUALTY` / `MISSING_PERSON` / `FIRE` /
  /// `FLOOD` / `HAZMAT` / `MEDICAL` / `EVACUATION` / `OTHER`. Null
  /// when not classifiable.
  final String? hazardType;

  /// HAZUS 0–4 — None / Slight / Moderate / Extensive / Complete.
  /// Set when a damage photo was analysed.
  final int? hazusCategory;

  /// `HAZUS_NONE` / `HAZUS_SLIGHT` / `HAZUS_MODERATE` /
  /// `HAZUS_EXTENSIVE` / `HAZUS_COMPLETE`. Paired with
  /// [hazusCategory].
  final String? femaScale;

  /// One-line damage description from photo. Null when no image.
  final String? damageDescription;

  /// START triage label — `ALIVE_SAFE` / `ALIVE_INJURED` /
  /// `ALIVE_TRAPPED` / `ALIVE_UNKNOWN` / `MISSING` / `DECEASED`.
  /// Set when the user describes a casualty.
  final String? casualtyStatus;

  /// Affected-person count when given. Empty list otherwise.
  final int? casualtyCount;

  /// `RED` / `YELLOW` / `GREEN` / `BLACK` / `UNTAGGED`. Paired with
  /// [casualtyStatus].
  final String? casualtyTriageColor;

  /// GPS line verbatim from the user prompt (e.g.
  /// `lat=19.20337, lng=72.82770 (±15m)`). Null when unavailable.
  final String? gps;

  /// Skill id the model picked from the registry. Null when none
  /// applies.
  final String? recommendedSkill;

  /// Short natural-language sentence the TTS should read aloud while
  /// the report card mounts. ≤2 sentences. Null when the card alone
  /// suffices (responder workflow, no TTS).
  final String? spokenSummary;

  Map<String, Object?> toJson() => <String, Object?>{
        'format': format,
        'title': title,
        'severity': severity,
        'summary': summary,
        'body': body,
        'immediate_actions': immediateActions,
        'prepared_at': preparedAt,
        'prepared_by': preparedBy,
        if (hazardType != null) 'hazard_type': hazardType,
        if (hazusCategory != null) 'hazus_category': hazusCategory,
        if (femaScale != null) 'fema_scale': femaScale,
        if (damageDescription != null) 'damage_description': damageDescription,
        if (casualtyStatus != null) 'casualty_status': casualtyStatus,
        if (casualtyCount != null) 'casualty_count': casualtyCount,
        if (casualtyTriageColor != null)
          'casualty_triage_color': casualtyTriageColor,
        if (gps != null) 'gps': gps,
        if (recommendedSkill != null) 'recommended_skill': recommendedSkill,
        if (spokenSummary != null) 'spoken_summary': spokenSummary,
      };

  factory TriageReport.fromJson(Map<String, Object?> json) {
    String str(String key, [String fallback = '']) =>
        (json[key] as String?)?.trim() ?? fallback;
    int? intOr(String key) => switch (json[key]) {
          final num n => n.toInt(),
          final String s => int.tryParse(s),
          _ => null,
        };
    List<String> stringList(String key) {
      final raw = json[key];
      if (raw is List) {
        return raw
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
      }
      return const <String>[];
    }

    return TriageReport(
      format: str('format', 'ICS-209'),
      title: str('title', 'Incident'),
      severity: str('severity', 'INFO').toUpperCase(),
      summary: str('summary'),
      body: str('body'),
      immediateActions: stringList('immediate_actions'),
      preparedAt: str('prepared_at'),
      preparedBy: str('prepared_by', 'Aegis Triage Auto-Draft'),
      hazardType: (json['hazard_type'] as String?)?.trim(),
      hazusCategory: intOr('hazus_category'),
      femaScale: (json['fema_scale'] as String?)?.trim(),
      damageDescription: (json['damage_description'] as String?)?.trim(),
      casualtyStatus: (json['casualty_status'] as String?)?.trim(),
      casualtyCount: intOr('casualty_count'),
      casualtyTriageColor: (json['casualty_triage_color'] as String?)?.trim(),
      gps: (json['gps'] as String?)?.trim(),
      recommendedSkill: (json['recommended_skill'] as String?)?.trim(),
      spokenSummary: (json['spoken_summary'] as String?)?.trim(),
    );
  }
}
