import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/voice/triage_report.dart';

/// Fixed Flutter card that renders a [TriageReport]. The model only
/// fills in the *data* — no JSON tree, no token-by-token surface
/// stream. Replaces the old A2UI catalog rendering path.
class TriageReportCard extends StatelessWidget {
  const TriageReportCard({
    super.key,
    required this.report,
    this.onConfirm,
    this.onReject,
  });

  final TriageReport report;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final enriched = _enrich(report);
    final accent = _severityColor(enriched.severity);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SeverityStrip(report: enriched, accent: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (enriched.summary.isNotEmpty)
                  SelectableText(
                    enriched.summary,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                const SizedBox(height: 14),
                _AssessmentRow(report: enriched),
                if (enriched.gps != null && enriched.gps!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _LocationChip(gps: enriched.gps!, accent: accent),
                ],
                if (enriched.immediateActions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ActionList(
                    actions: enriched.immediateActions,
                    accent: accent,
                  ),
                ],
                if (enriched.body.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _ReportBodySection(
                    format: enriched.format,
                    body: enriched.body,
                    accent: accent,
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                _MetadataStrip(report: enriched),
                if (onConfirm != null || onReject != null) ...[
                  const SizedBox(height: 14),
                  _ConfirmRow(onConfirm: onConfirm, onReject: onReject),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pre-render fixup. Gemma 4 emits structured fields imperfectly:
  ///   * `title` is sometimes the generic placeholder "Incident" — pull
  ///     the real title from the body's `Incident Name:` line.
  ///   * `immediate_actions` is sometimes empty — pull a numbered list
  ///     out of the body.
  ///   * `hazus_category` and `fema_scale` disagree (category 0 +
  ///     HAZUS_MODERATE) — derive category from the scale when scale is
  ///     non-NONE.
  ///   * `body` repeats fields the chrome already shows — strip them.
  static TriageReport _enrich(TriageReport r) {
    var title = r.title;
    if (_isGenericTitle(title)) {
      final fromBody = _extractFromBody(r.body, _titleLabels);
      if (fromBody != null && fromBody.isNotEmpty) title = fromBody;
    }

    var actions = r.immediateActions;
    if (actions.isEmpty) {
      actions = _extractNumberedListFromBody(r.body);
    }

    var hazusCategory = r.hazusCategory;
    final scale = r.femaScale;
    if (scale != null && scale != 'HAZUS_NONE' &&
        (hazusCategory == null || hazusCategory == 0)) {
      hazusCategory = _scaleToCategory(scale);
    }

    final cleanedBody = _cleanReportBody(r.body, actions);

    return TriageReport(
      format: r.format,
      title: title,
      severity: r.severity,
      summary: r.summary,
      body: cleanedBody,
      immediateActions: actions,
      preparedAt: r.preparedAt,
      preparedBy: r.preparedBy,
      hazardType: r.hazardType,
      hazusCategory: hazusCategory,
      femaScale: r.femaScale,
      damageDescription: r.damageDescription,
      casualtyStatus: r.casualtyStatus,
      casualtyCount: r.casualtyCount,
      casualtyTriageColor: r.casualtyTriageColor,
      gps: r.gps,
      recommendedSkill: r.recommendedSkill,
      spokenSummary: r.spokenSummary,
    );
  }

  static const _titleLabels = <String>[
    'incident name',
    'event name',
    'incident',
    'event',
    'title',
  ];

  static bool _isGenericTitle(String t) {
    final n = t.trim().toLowerCase();
    if (n.isEmpty) return true;
    return n == 'incident' || n == 'event' || n == 'report' || n == 'title';
  }

  static String? _extractFromBody(String body, List<String> labels) {
    for (final line in body.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final label = line.substring(0, colon).trim().toLowerCase();
      if (!labels.contains(label)) continue;
      final value = line.substring(colon + 1).trim();
      if (value.isEmpty) continue;
      return value;
    }
    return null;
  }

  static final RegExp _numberedItem =
      RegExp(r'^\s*(?:\d+|[ivx]+)[\.\)]\s+(.+?)\s*$', caseSensitive: false);

  static List<String> _extractNumberedListFromBody(String body) {
    final out = <String>[];
    for (final line in body.split('\n')) {
      final m = _numberedItem.firstMatch(line);
      if (m == null) continue;
      final item = m.group(1)!.trim();
      if (item.length < 4) continue;
      out.add(item);
    }
    return out.take(5).toList();
  }

  static int _scaleToCategory(String scale) => switch (scale) {
        'HAZUS_NONE' => 0,
        'HAZUS_SLIGHT' => 1,
        'HAZUS_MODERATE' => 2,
        'HAZUS_EXTENSIVE' => 3,
        'HAZUS_COMPLETE' => 4,
        _ => 0,
      };

  /// Strip lines from the report body that duplicate fields already
  /// rendered as structured chrome (severity badge, title, summary,
  /// immediate actions, GPS pill, damage tile, casualty tile). Also
  /// drop `[INFERRED — verify before submission]` orphan lines and
  /// the numbered action list that was extracted into the chrome.
  static String _cleanReportBody(String body, List<String> extractedActions) {
    if (body.isEmpty) return '';
    final dropLabels = <RegExp>[
      // Chrome dupes
      RegExp(r'^\s*title\s*:', caseSensitive: false),
      RegExp(r'^\s*severity\s*:', caseSensitive: false),
      RegExp(r'^\s*summary\s*:', caseSensitive: false),
      RegExp(r'^\s*format\s*:', caseSensitive: false),
      RegExp(r'^\s*report\s+format\s*:', caseSensitive: false),
      RegExp(r'^\s*incident\s+name\s*:', caseSensitive: false),
      RegExp(r'^\s*event\s+name\s*:', caseSensitive: false),
      RegExp(r'^\s*incident\s+type\s*:', caseSensitive: false),
      RegExp(r'^\s*event\s+type\s*:', caseSensitive: false),
      // Timestamp dupes — metadata strip shows formatted version
      RegExp(r'^\s*date\s*/?\s*time\s*:', caseSensitive: false),
      RegExp(r'^\s*timestamp\s*:', caseSensitive: false),
      RegExp(r'^\s*captured\s*(?:at)?\s*:', caseSensitive: false),
      RegExp(r'^\s*reported\s*at\s*:', caseSensitive: false),
      RegExp(r'^\s*prepared\s*(?:at|by)\s*:', caseSensitive: false),
      // Extracted into chrome
      RegExp(r'^\s*immediate\s+actions?\s*:?\s*$', caseSensitive: false),
      RegExp(r'^\s*actions?\s*:?\s*$', caseSensitive: false),
      RegExp(r'^\s*recommended\s+actions?\s*:?\s*$', caseSensitive: false),
      RegExp(r'^\s*next\s+steps?\s*:?\s*$', caseSensitive: false),
      // Location chrome dupes
      RegExp(r'^\s*gps\s*:', caseSensitive: false),
      RegExp(r'^\s*coordinates?\s*:', caseSensitive: false),
      RegExp(r'^\s*location\s*:\s*lat\s*=?', caseSensitive: false),
      // Assessment chrome dupes
      RegExp(r'^\s*fema\s*scale\s*:', caseSensitive: false),
      RegExp(r'^\s*hazus\s*category\s*:', caseSensitive: false),
      RegExp(r'^\s*hazard\s*type\s*:', caseSensitive: false),
      RegExp(r'^\s*casualty\s*status\s*:', caseSensitive: false),
      RegExp(r'^\s*casualty\s*count\s*:', caseSensitive: false),
      RegExp(r'^\s*triage\s*colou?r\s*:', caseSensitive: false),
      // Recommend skill chrome dupe
      RegExp(r'^\s*recommended\s*skill\s*:', caseSensitive: false),
    ];

    // Normalize extracted action items so we can match the body lines
    // that became those actions. Compare by lowercase trimmed text.
    final actionSet = <String>{
      for (final a in extractedActions) a.trim().toLowerCase(),
    };
    final orphanMarkers = RegExp(
      r'^\s*\[\s*inferred\s*—?-?\s*verify[^\]]*\]\s*$',
      caseSensitive: false,
    );
    final pureArray =
        RegExp(r'^\s*\[\s*["“].*["”]\s*\]\s*$', dotAll: true);
    final numberedItem =
        RegExp(r'^\s*(?:\d+|[ivx]+)[\.\)]\s+(.+?)\s*$', caseSensitive: false);

    final kept = <String>[];
    for (final line in body.split('\n')) {
      if (dropLabels.any((re) => re.hasMatch(line))) continue;
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        kept.add(line);
        continue;
      }
      if (orphanMarkers.hasMatch(trimmed)) continue;
      if (pureArray.hasMatch(trimmed)) continue;
      final numbered = numberedItem.firstMatch(trimmed);
      if (numbered != null) {
        final item = numbered.group(1)!.trim().toLowerCase();
        if (actionSet.contains(item)) continue;
      }
      kept.add(line);
    }
    // Collapse runs of blank lines + trim outer whitespace.
    final out = StringBuffer();
    var prevBlank = false;
    for (final line in kept) {
      final blank = line.trim().isEmpty;
      if (blank && prevBlank) continue;
      out.writeln(line);
      prevBlank = blank;
    }
    return out.toString().trim();
  }

  static Color _severityColor(String severity) => switch (severity) {
        'CRITICAL' => Colors.red.shade700,
        'HIGH' => Colors.deepOrange.shade600,
        'MODERATE' => Colors.amber.shade700,
        'LOW' => Colors.lightGreen.shade700,
        _ => AegisColors.primary,
      };
}

/// Full-width banner across the top of the card. Severity tint
/// dominates so HIGH / CRITICAL reads at-a-glance. Title + small pill
/// row sit on the tinted band.
class _SeverityStrip extends StatelessWidget {
  const _SeverityStrip({required this.report, required this.accent});
  final TriageReport report;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final hazardLabel = _hazardLabel(report);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.06),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _severityIcon(report.severity),
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Pill(text: report.severity, color: accent, filled: true),
                    _Pill(text: report.format, color: AegisColors.primary),
                    if (hazardLabel != null)
                      _Pill(
                        text: hazardLabel,
                        color: AegisColors.onSurfaceMuted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hide the hazard pill when it would duplicate severity (`CASUALTY`
  /// is already represented by the casualty tile, `STRUCTURAL_DAMAGE`
  /// by the damage tile). Keep it only when it adds context the body
  /// chrome doesn't already convey (FIRE, FLOOD, HAZMAT, MEDICAL,
  /// EVACUATION, MISSING_PERSON).
  static String? _hazardLabel(TriageReport r) {
    final h = r.hazardType?.trim();
    if (h == null || h.isEmpty) return null;
    const redundant = <String>{
      'CASUALTY',
      'STRUCTURAL_DAMAGE',
      'OTHER',
    };
    if (redundant.contains(h)) return null;
    return h.replaceAll('_', ' ');
  }

  static IconData _severityIcon(String s) => switch (s) {
        'CRITICAL' || 'HIGH' => Icons.warning_amber_rounded,
        'MODERATE' => Icons.report_problem_outlined,
        'LOW' => Icons.info_outline,
        _ => Icons.assignment_outlined,
      };
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.color,
    this.filled = false,
  });
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ActionList extends StatelessWidget {
  const _ActionList({required this.actions, required this.accent});
  final List<String> actions;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.checklist_rtl, size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              'Immediate actions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < actions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    actions[i],
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AssessmentRow extends StatelessWidget {
  const _AssessmentRow({required this.report});
  final TriageReport report;

  @override
  Widget build(BuildContext context) {
    // Always render both tiles side by side. Empty fields fall back to
    // "None reported" so the responder sees a complete summary at a
    // glance — never a missing card.
    final cat = report.hazusCategory;
    final scale = report.femaScale;
    final desc = report.damageDescription;
    final hasMeaningfulDamage =
        (cat != null && cat > 0) ||
            (scale != null && scale.isNotEmpty && scale != 'HAZUS_NONE') ||
            (desc != null && desc.trim().isNotEmpty);

    final hasCasualty = report.casualtyStatus != null ||
        report.casualtyCount != null ||
        (report.casualtyTriageColor?.isNotEmpty ?? false);

    final damageTile = hasMeaningfulDamage
        ? _AssessmentTile(
            icon: Icons.broken_image_outlined,
            title: 'Damage',
            primary: _hazusLabel(scale, cat),
            secondary: _hazusCategoryLabel(cat),
            accent: _hazusColor(cat ?? _scaleToCategory(scale ?? 'HAZUS_NONE')),
            detail: desc,
          )
        : _AssessmentTile(
            icon: Icons.broken_image_outlined,
            title: 'Damage',
            primary: 'None reported',
            secondary: 'No structural damage',
            accent: Colors.grey.shade500,
            muted: true,
          );

    final casualtyTile = hasCasualty
        ? _AssessmentTile(
            icon: Icons.medical_services_outlined,
            title: 'Casualty',
            primary: (report.casualtyStatus ?? 'UNKNOWN').replaceAll('_', ' '),
            secondary: _casualtySecondary(report),
            accent: _triageColor(report.casualtyTriageColor),
          )
        : _AssessmentTile(
            icon: Icons.medical_services_outlined,
            title: 'Casualty',
            primary: 'None reported',
            secondary: 'No casualties',
            accent: Colors.grey.shade500,
            muted: true,
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: damageTile),
        const SizedBox(width: 8),
        Expanded(child: casualtyTile),
      ],
    );
  }

  static String _casualtySecondary(TriageReport r) {
    final color = r.casualtyTriageColor;
    final count = r.casualtyCount;
    if (count != null && color != null && color.isNotEmpty) {
      return '$count reported · $color';
    }
    if (count != null) return '$count reported';
    return color ?? 'UNTAGGED';
  }

  static String _hazusLabel(String? scale, int? cat) {
    if (scale != null && scale.isNotEmpty) {
      return scale.replaceFirst('HAZUS_', '').toUpperCase();
    }
    if (cat == null) return 'NONE';
    return switch (cat) {
      0 => 'NONE',
      1 => 'SLIGHT',
      2 => 'MODERATE',
      3 => 'EXTENSIVE',
      4 => 'COMPLETE',
      _ => 'NONE',
    };
  }

  static String _hazusCategoryLabel(int? cat) {
    if (cat == null) return 'HAZUS scale';
    return 'HAZUS · Cat $cat';
  }

  static int _scaleToCategory(String scale) => switch (scale) {
        'HAZUS_NONE' => 0,
        'HAZUS_SLIGHT' => 1,
        'HAZUS_MODERATE' => 2,
        'HAZUS_EXTENSIVE' => 3,
        'HAZUS_COMPLETE' => 4,
        _ => 0,
      };

  static Color _hazusColor(int category) => switch (category) {
        0 => Colors.green.shade600,
        1 => Colors.lightGreen.shade700,
        2 => Colors.amber.shade700,
        3 => Colors.deepOrange.shade600,
        4 => Colors.red.shade700,
        _ => Colors.grey,
      };

  static Color _triageColor(String? code) => switch (code?.toUpperCase()) {
        'RED' => Colors.red.shade700,
        'YELLOW' => Colors.amber.shade700,
        'GREEN' => Colors.green.shade600,
        'BLACK' => Colors.black87,
        _ => Colors.grey,
      };
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({
    required this.icon,
    required this.title,
    required this.primary,
    required this.secondary,
    required this.accent,
    this.detail,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String primary;
  final String secondary;
  final Color accent;
  final String? detail;

  /// Placeholder tile (no real data). Quieter chrome so it doesn't
  /// compete with the data-bearing tile next to it.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final bgAlpha = muted ? 0.03 : 0.06;
    final borderAlpha = muted ? 0.18 : 0.25;
    final primaryStyle = TextStyle(
      fontSize: 13,
      fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
      color: muted ? AegisColors.onSurfaceMuted : AegisColors.onSurface,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: borderAlpha)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(primary, style: primaryStyle),
          Text(
            secondary,
            style: const TextStyle(
              fontSize: 11,
              color: AegisColors.onSurfaceMuted,
            ),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportBodySection extends StatefulWidget {
  const _ReportBodySection({
    required this.format,
    required this.body,
    required this.accent,
  });
  final String format;
  final String body;
  final Color accent;

  @override
  State<_ReportBodySection> createState() => _ReportBodySectionState();
}

class _ReportBodySectionState extends State<_ReportBodySection> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AegisColors.onSurfaceMuted.withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _open = !_open),
            child: Container(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(10),
                  bottom: _open ? Radius.zero : const Radius.circular(10),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.format} report',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: accent,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: IncidentReportBody(body: widget.body, accent: accent),
            ),
        ],
      ),
    );
  }
}

class _MetadataStrip extends StatelessWidget {
  const _MetadataStrip({required this.report});
  final TriageReport report;

  @override
  Widget build(BuildContext context) {
    final pairs = <(IconData, String)>[
      (Icons.access_time, _formatTimestamp(report.preparedAt)),
      (Icons.edit_outlined, report.preparedBy),
      if (report.recommendedSkill != null &&
          report.recommendedSkill!.isNotEmpty)
        (Icons.extension_outlined, report.recommendedSkill!),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final p in pairs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(p.$1, size: 12, color: AegisColors.onSurfaceMuted),
              const SizedBox(width: 4),
              Text(
                p.$2,
                style: const TextStyle(
                  fontSize: 11,
                  color: AegisColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Be lenient about ISO drift. Gemma 4 emits the timestamp many ways:
  ///   * Standard `2026-05-12T17:43:24Z`
  ///   * Compact `20260512T174324Z` / `20260512174324Z`
  ///   * Mangled `206-0-12011110557Z` / `20260202011105557Z` (digit
  ///     run-on / dropped leading zeros)
  /// Try parsing each form, accept only years within ±1 of "now". If
  /// nothing lands in range, the model hallucinated — fall back to
  /// "Just captured" using the device clock.
  static String _formatTimestamp(String iso) {
    final trimmed = iso.trim();
    if (trimmed.isEmpty) return _humanize(DateTime.now());
    final nowYear = DateTime.now().year;
    final candidates = <String>{
      trimmed,
      _normalizeCompactIso(trimmed),
      _forceFromDigits(trimmed),
    };
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final parsed = DateTime.tryParse(candidate);
      if (parsed == null) continue;
      // Accept only the present-day window. Year 2030 / 2060 from a
      // mangled model output is garbage; fall through to capture time.
      if (parsed.year < nowYear - 1 || parsed.year > nowYear + 1) continue;
      return _humanize(parsed.toLocal());
    }
    return _humanize(DateTime.now());
  }

  /// `2026-05-12 23:13` — short human form, no timezone suffix.
  static String _humanize(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final mo = months[t.month - 1];
    final d = t.day;
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    return '$d $mo ${t.year} · $h:$mi';
  }

  /// `20260512174324Z` → `2026-05-12T17:43:24Z`.
  static String _normalizeCompactIso(String s) {
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})T?(\d{2})(\d{2})(\d{2})Z?$');
    final m = compact.firstMatch(s);
    if (m == null) return '';
    return '${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}Z';
  }

  /// Last-ditch parse: pull every digit out of [s] and force-decode the
  /// first 14 as `YYYYMMDDhhmmss`. Recovers `206-0-12011110557Z` →
  /// digits `2060120111105 57` → first 14 = `20601201111055` → parses
  /// as 2060-12-01 11:10:55 which is rejected by the year > 2100 guard,
  /// so we also try a slide that prepends a missing leading `20`.
  static String _forceFromDigits(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 12) return '';
    final variants = <String>[];
    if (digits.length >= 14) variants.add(digits.substring(0, 14));
    if (digits.length >= 12) variants.add('${digits.substring(0, 12)}00');
    // Try left-padding when first chars look like a truncated year
    // (e.g. `2060...` is unlikely; `20260202...` is likely with one
    // extra digit). We don't aggressively guess — the parsed-year
    // guard in [_formatTimestamp] rejects garbage.
    for (final v in variants) {
      if (v.length != 14) continue;
      final y = v.substring(0, 4);
      final mo = v.substring(4, 6);
      final d = v.substring(6, 8);
      final h = v.substring(8, 10);
      final mi = v.substring(10, 12);
      final se = v.substring(12, 14);
      return '$y-$mo-${d}T$h:$mi:${se}Z';
    }
    return '';
  }
}

/// Prominent location chip rendered right under the assessment tiles.
/// Pulls lat/lng out of the GPS string so we can show readable values
/// even when the model padded the line with extras.
class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.gps, required this.accent});
  final String gps;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final parsed = _parse(gps);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  parsed.primary,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (parsed.secondary.isNotEmpty)
                  Text(
                    parsed.secondary,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AegisColors.onSurfaceMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static ({String primary, String secondary}) _parse(String raw) {
    final latRe = RegExp(r'lat\s*=\s*(-?\d+(?:\.\d+)?)', caseSensitive: false);
    final lngRe = RegExp(r'(?:lng|lon)\s*=\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false);
    final accRe = RegExp(r'±\s*(\d+(?:\.\d+)?)\s*m', caseSensitive: false);
    final lat = latRe.firstMatch(raw)?.group(1);
    final lng = lngRe.firstMatch(raw)?.group(1);
    final acc = accRe.firstMatch(raw)?.group(1);
    if (lat != null && lng != null) {
      final primary = '$lat°, $lng°';
      final secondary = acc != null ? 'GPS accuracy ±${acc}m' : 'GPS fix';
      return (primary: primary, secondary: secondary);
    }
    return (primary: raw, secondary: '');
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({this.onConfirm, this.onReject});
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onReject != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.refresh),
              label: const Text('Reject'),
            ),
          ),
        if (onReject != null && onConfirm != null) const SizedBox(width: 12),
        if (onConfirm != null)
          Expanded(
            child: FilledButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check),
              label: const Text('Confirm'),
            ),
          ),
      ],
    );
  }
}

/// Renders a multi-format disaster-report body as structured UI.
/// Detects section headings, `LABEL: VALUE` field rows, and free-form
/// lines. `[INFERRED]` / `[UNKNOWN]` markers get an amber chip pill.
class IncidentReportBody extends StatelessWidget {
  const IncidentReportBody({
    super.key,
    required this.body,
    this.accent,
  });

  final String body;

  /// Severity accent threaded through from the parent card. When null,
  /// the body falls back to the app primary color (used in standalone
  /// previews / tests).
  final Color? accent;

  static final RegExp _fieldPattern = RegExp(r'^\s*([^:\n]{1,80}?):\s*(.*)$');
  static final RegExp _placeholderPattern =
      RegExp(r'\[(?:INFERRED|UNKNOWN)[^\]]*\]', caseSensitive: false);
  static final RegExp _fullPlaceholder =
      RegExp(r'^\s*\[(?:INFERRED|UNKNOWN)[^\]]*\]\s*$', caseSensitive: false);

  static String _cleanHeading(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'^[─━—=─]+|[─━—=─]+\$'), '').trim();
    s = s.replaceAll(RegExp(r'\s+[─━—=─]+\s*'), ' ').trim();
    if (s.replaceAll(RegExp(r'[─━—=─\s]'), '').isEmpty) return '';
    final words = s.split(RegExp(r'\s+'));
    return words.map((w) {
      if (w.isEmpty) return w;
      if (w.length <= 3 && w == w.toUpperCase()) return w;
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  static String _cleanLabel(String raw) {
    var s = raw.trim();
    s = s.replaceFirst(
        RegExp(r'^(?:BLOCK|SECTION|ITEM)\s+\d+[A-Za-z]?\.?\s*',
            caseSensitive: false),
        '');
    s = s.replaceFirst(RegExp(r'^\d+(?:\.\d+)?\.?\s*'), '');
    if (s.isEmpty) return raw.trim();
    final words = s.split(RegExp(r'\s+'));
    return words.map((w) {
      if (w.isEmpty) return w;
      if (w.length <= 3 && w == w.toUpperCase()) return w;
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }

  bool _isHeading(String line) {
    final stripped = line.trim();
    if (stripped.isEmpty) return false;
    if (stripped.length < 3) return false;
    if (stripped.contains(':') && !stripped.endsWith(':')) return false;
    final letters = stripped.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return false;
    final upperRatio =
        letters.split('').where((c) => c == c.toUpperCase()).length /
            letters.length;
    return upperRatio > 0.85;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const Text(
        '(empty report)',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    // Group consecutive non-heading lines under each section heading.
    final sections = _groupSections(trimmed);
    final widgets = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      if (i > 0) widgets.add(const SizedBox(height: 10));
      if (s.heading != null) {
        widgets.add(_SectionHeading(
          text: s.heading!,
          accent: accent ?? AegisColors.primary,
        ));
        widgets.add(const SizedBox(height: 4));
      }
      for (final line in s.lines) {
        if (line.trim().isEmpty) continue;
        final match = _fieldPattern.firstMatch(line);
        if (match != null) {
          final label = _cleanLabel(match.group(1)!);
          final value = match.group(2)!.trim();
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _ReportFieldRow(label: label, value: value),
          ));
        } else {
          widgets.add(Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SelectableText(
              line.trim(),
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ));
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  List<_Section> _groupSections(String body) {
    final sections = <_Section>[];
    _Section current = _Section(heading: null, lines: <String>[]);
    for (final raw in body.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        // Blank line — flush current section if it has content.
        if (current.lines.isNotEmpty || current.heading != null) {
          sections.add(current);
          current = _Section(heading: null, lines: <String>[]);
        }
        continue;
      }
      if (_isHeading(line)) {
        if (current.lines.isNotEmpty || current.heading != null) {
          sections.add(current);
        }
        final h = _cleanHeading(line);
        current = _Section(heading: h.isEmpty ? null : h, lines: <String>[]);
        continue;
      }
      current.lines.add(line);
    }
    if (current.lines.isNotEmpty || current.heading != null) {
      sections.add(current);
    }
    return sections;
  }
}

class _Section {
  _Section({required this.heading, required this.lines});
  final String? heading;
  final List<String> lines;
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.text, required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

/// Subtle "needs input" marker — replaces the loud amber
/// `[INFERRED — verify before submission]` chip. Communicates "this
/// field needs the responder's input" without yelling.
class _NeedsInputPill extends StatelessWidget {
  const _NeedsInputPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AegisColors.onSurfaceMuted.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_outlined,
            size: 11,
            color: AegisColors.onSurfaceMuted.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 4),
          Text(
            'needs input',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AegisColors.onSurfaceMuted.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportFieldRow extends StatelessWidget {
  const _ReportFieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelText = '$label:';
    final spans = <InlineSpan>[];
    if (value.isEmpty) {
      spans.add(const TextSpan(
        text: '—',
        style: TextStyle(color: Colors.black38),
      ));
    } else {
      // If the whole value is just a placeholder, render it as muted
      // italic "needs input" — clearer than the old amber chip which
      // looked like a status badge. Mixed text + placeholder still
      // renders the surrounding text plain.
      final fullPlaceholder = IncidentReportBody._fullPlaceholder
          .firstMatch(value.trim());
      if (fullPlaceholder != null) {
        spans.add(const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _NeedsInputPill(),
        ));
      } else {
        var cursor = 0;
        for (final match
            in IncidentReportBody._placeholderPattern.allMatches(value)) {
          if (match.start > cursor) {
            spans.add(TextSpan(text: value.substring(cursor, match.start)));
          }
          spans.add(const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _NeedsInputPill(),
          ));
          cursor = match.end;
        }
        if (cursor < value.length) {
          spans.add(TextSpan(text: value.substring(cursor)));
        }
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 160),
          padding: const EdgeInsets.only(right: 8, top: 1),
          child: Text(
            labelText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ),
        Expanded(
          child: SelectableText.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12, height: 1.4),
              children: spans,
            ),
          ),
        ),
      ],
    );
  }
}
