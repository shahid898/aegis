import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/di/injection.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/widgets/aegis_audio_chip.dart';
import '../../home/widgets/triage_report_card.dart';
import '../data/report.dart';
import '../data/reports_repository.dart';

/// Reports archive — every confirmed triage card lands here. Two
/// screens in one file:
///   * [ReportsPage] — list view, newest first, with delete-on-swipe.
///   * [_ReportDetailPage] — renders the persisted [TriageReport] via
///     [TriageReportCard] (the same widget the home page uses).
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final repo = sl<ReportsRepository>();
    return Scaffold(
      appBar: AppBar(title: Text(l.reportsTitle)),
      body: ValueListenableBuilder<List<Report>>(
        valueListenable: repo.listenable,
        builder: (context, reports, _) {
          if (reports.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: reports.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ReportTile(
              report: reports[index],
              onTap: () => _open(context, reports[index]),
              onDelete: () => repo.delete(reports[index].id),
            ),
          );
        },
      ),
    );
  }

  void _open(BuildContext context, Report report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReportDetailPage(report: report),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 64,
              color: AegisColors.onSurfaceMuted,
            ),
            const SizedBox(height: 12),
            Text(
              l.reportsEmpty,
              style: const TextStyle(
                color: AegisColors.onSurfaceMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.reportsEmptyHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AegisColors.onSurfaceMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.onTap,
    required this.onDelete,
  });

  final Report report;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final time =
        DateFormat.yMMMd().add_jm().format(report.createdAt.toLocal());
    final decoded = report.report;
    final title = decoded?.title ?? report.userText;
    final subtitle = decoded?.summary.isNotEmpty == true
        ? decoded!.summary
        : _oneLine(report.assistantText);
    return Dismissible(
      key: ValueKey(report.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AegisColors.danger.withValues(alpha: 0.85),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l.reportsDelete),
                content: Text(l.reportsDeleteBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l.reportsCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(l.reportsDeleteAction),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: const Icon(Icons.dashboard_customize_outlined),
        title: Text(
          title.isEmpty ? l.reportsNoInputText : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle.isEmpty ? time : '$time · $subtitle',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  static String _oneLine(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _ReportDetailPage extends StatefulWidget {
  const _ReportDetailPage({required this.report});

  final Report report;

  @override
  State<_ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<_ReportDetailPage> {
  Uint8List? _image;
  Uint8List? _audio;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    final r = widget.report;
    Uint8List? image;
    Uint8List? audio;
    try {
      final p = r.imagePath;
      if (p != null && p.isNotEmpty) {
        final f = File(p);
        if (await f.exists()) image = await f.readAsBytes();
      }
    } on Object catch (e) {
      debugPrint('[Aegis][ReportDetail] image load failed: $e');
    }
    try {
      final p = r.audioPath;
      if (p != null && p.isNotEmpty) {
        final f = File(p);
        if (await f.exists()) audio = await f.readAsBytes();
      }
    } on Object catch (e) {
      debugPrint('[Aegis][ReportDetail] audio load failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _image = image;
      _audio = audio;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final time = DateFormat.yMMMd()
        .add_jm()
        .format(widget.report.createdAt.toLocal());
    final decoded = widget.report.report;
    return Scaffold(
      appBar: AppBar(title: Text(l.reportsDetailTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AegisColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: AegisColors.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.report.userText.isEmpty
                          ? l.reportsYouEvidenceOnly
                          : l.reportsYouQuote(widget.report.userText),
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                  ],
                ),
              ),
              if (_image != null && _image!.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_image!),
                ),
              ],
              if (_audio != null && _audio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                AegisAudioChip(wavBytes: _audio!),
              ],
              if (widget.report.assistantText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    widget.report.assistantText,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (decoded == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      l.reportsLegacy,
                      style: const TextStyle(
                        color: AegisColors.onSurfaceMuted,
                      ),
                    ),
                  ),
                )
              else
                TriageReportCard(report: decoded),
            ],
          ),
        ),
      ),
    );
  }
}
