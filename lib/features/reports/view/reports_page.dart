import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart' as genui;
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/di/injection.dart';
import '../../home/cubit/assistant_cubit.dart';
import '../../home/widgets/aegis_catalog.dart';
import '../data/report.dart';
import '../data/reports_repository.dart';

/// Reports archive — every confirmed triage card lands here. The user
/// reaches this page from the history icon in the home header.
///
/// Two screens in one file:
///   * [ReportsPage] — list view, newest first, with delete-on-swipe.
///   * [_ReportDetailPage] — surface replay using the same Aegis
///     catalog so the rendered card matches what the user originally
///     confirmed.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = sl<ReportsRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Triage Reports')),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: AegisColors.onSurfaceMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No reports yet.',
              style: TextStyle(
                color: AegisColors.onSurfaceMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "Start triage" on the home screen to draft one.',
              textAlign: TextAlign.center,
              style: TextStyle(
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
    final time = DateFormat.yMMMd().add_jm().format(report.createdAt.toLocal());
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
                title: const Text('Delete report?'),
                content: const Text(
                  'This removes the report from the archive. '
                  'Cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Delete'),
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
          report.userText.isEmpty ? '(no input text)' : report.userText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          report.assistantText.isEmpty
              ? time
              : '$time · ${_oneLine(report.assistantText)}',
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

/// Replays the report's saved raw LLM output through
/// [genui.A2uiParserTransformer] into a private [genui.SurfaceController]
/// so the original card renders identical to confirm-time. We mount
/// the same Aegis catalog the home page uses — no surface drift.
class _ReportDetailPage extends StatefulWidget {
  const _ReportDetailPage({required this.report});

  final Report report;

  @override
  State<_ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<_ReportDetailPage> {
  late final genui.Catalog _catalog;
  late final genui.SurfaceController _controller;
  StreamController<String>? _input;
  StreamSubscription<genui.GenerationEvent>? _sub;
  String? _surfaceId;
  String _replayedText = '';

  @override
  void initState() {
    super.initState();
    _catalog = buildAegisCatalog();
    _controller = genui.SurfaceController(catalogs: [_catalog]);
    _replay();
  }

  Future<void> _replay() async {
    // Re-publish the report's saved attachments to the global
    // evidence sink BEFORE the IncidentReportCard mounts. The card's
    // `_EvidenceBlock` reads from `AssistantCubit.evidenceSink` (a
    // top-level ValueNotifier — see AssistantCubit for why we don't
    // use a BlocProvider here), and that sink is in-memory only,
    // empty after a hot-restart. Loading the persisted bytes here
    // means opening a saved report repopulates the image + voice
    // chips identically to the moment it was confirmed.
    await _hydrateEvidenceFromReport();

    final input = StreamController<String>();
    _input = input;
    final textBuffer = StringBuffer();
    _sub = input.stream
        .transform(const genui.A2uiParserTransformer())
        .listen((event) {
      if (event is genui.A2uiMessageEvent) {
        if (_surfaceId == null && event.message is genui.CreateSurface) {
          _surfaceId = (event.message as genui.CreateSurface).surfaceId;
          if (mounted) setState(() {});
        }
        _controller.handleMessage(event.message);
      } else if (event is genui.TextEvent) {
        textBuffer.write(event.text);
      }
    });
    input.add(widget.report.rawLlmOutput);
    await input.close();
    await _sub?.asFuture<void>();
    if (mounted) {
      setState(() => _replayedText = textBuffer.toString().trim());
    }
  }

  Future<void> _hydrateEvidenceFromReport() async {
    final r = widget.report;
    Uint8List? image;
    Uint8List? audio;
    final imagePath = r.imagePath;
    final audioPath = r.audioPath;
    try {
      if (imagePath != null && imagePath.isNotEmpty) {
        final f = File(imagePath);
        if (await f.exists()) image = await f.readAsBytes();
      }
    } on Object catch (e) {
      debugPrint('[Aegis][ReportDetail] image load failed: $e');
    }
    try {
      if (audioPath != null && audioPath.isNotEmpty) {
        final f = File(audioPath);
        if (await f.exists()) audio = await f.readAsBytes();
      }
    } on Object catch (e) {
      debugPrint('[Aegis][ReportDetail] audio load failed: $e');
    }
    AssistantCubit.evidenceSink.value = AssistantEvidenceSnapshot(
      image: image,
      audio: audio,
      text: r.userText,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input?.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.yMMMd()
        .add_jm()
        .format(widget.report.createdAt.toLocal());
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
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
                      'You: "${widget.report.userText}"',
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                  ],
                ),
              ),
              if (_replayedText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    _replayedText,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_surfaceId == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      '(no surface to replay — text-only report)',
                      style: TextStyle(color: AegisColors.onSurfaceMuted),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AegisColors.onSurfaceMuted.withValues(alpha: 0.15),
                    ),
                  ),
                  child: genui.Surface(
                    surfaceContext: _controller.contextFor(_surfaceId!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
