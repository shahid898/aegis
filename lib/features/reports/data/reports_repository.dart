import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/constants/storage_keys.dart';
import 'report.dart';

/// Hive-backed store for confirmed triage reports.
///
/// Lives in its own box so prefs / contacts / reports can scale
/// independently. Stores each report as a JSON string keyed by
/// [Report.id] (an ISO timestamp). Exposes a [ValueListenable] of the
/// latest snapshot so the Reports page can rebuild as new reports
/// land or get deleted.
class ReportsRepository {
  ReportsRepository._(this._box);

  final Box<String> _box;
  final ValueNotifier<List<Report>> _listenable = ValueNotifier(const []);

  /// Snapshot of the report list, newest first. Refreshed on every
  /// mutation so [ReportsPage] can drive a [ValueListenableBuilder]
  /// against this without any Hive imports of its own.
  ValueListenable<List<Report>> get listenable => _listenable;

  static Future<ReportsRepository> open() async {
    final box = await Hive.openBox<String>(StorageBoxes.reports);
    final repo = ReportsRepository._(box);
    repo._refresh();
    return repo;
  }

  Future<void> save(Report report) async {
    await _box.put(report.id, jsonEncode(report.toJson()));
    _refresh();
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    _refresh();
  }

  Future<void> clear() async {
    await _box.clear();
    _refresh();
  }

  Report? byId(String id) {
    final raw = _box.get(id);
    if (raw == null) return null;
    return Report.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  void _refresh() {
    final reports = <Report>[];
    for (final raw in _box.values) {
      try {
        reports.add(
          Report.fromJson(jsonDecode(raw) as Map<String, Object?>),
        );
      } on FormatException {
        // Skip a single corrupt entry rather than failing the whole
        // list — the user can still see other reports.
        continue;
      }
    }
    reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _listenable.value = List.unmodifiable(reports);
  }
}
