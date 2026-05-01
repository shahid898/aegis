import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import 'skill.dart';

/// Loads SKILL.md files from `assets/skills/<id>/SKILL.md`, parses
/// their YAML frontmatter, and exposes them as a discoverable catalog.
///
/// The registry is the bridge between markdown and Gemma 4: at chat
/// creation we call [buildCatalogPrompt] and concatenate the result
/// into the system prompt so the model can pick a skill by id.
///
/// **Why markdown, not Dart classes.** Aegis ships as extensible
/// infrastructure — partner orgs (WHO, IFRC, ICRC) need to ship
/// skills without compiling Dart. A new SKILL.md dropped into
/// `assets/skills/` becomes a first-class capability after a hot
/// restart, no code review of pure-Dart dispatch tables required.
class SkillsRegistry {
  SkillsRegistry({List<String>? skillIds})
    : _skillIds = skillIds ?? _builtInSkillIds;

  /// IDs that ship inside the app bundle. Each one corresponds to a
  /// directory under `assets/skills/` declared in `pubspec.yaml`.
  static const List<String> _builtInSkillIds = [
    'compose-briefing',
    'plan-evacuation-route',
    'grade-damage-hazus',
    'intake-survivor-statement',
    'generate-ics-209',
    'match-mesh-beacon',
  ];

  final List<String> _skillIds;
  List<Skill>? _cached;
  Future<List<Skill>>? _loadFuture;

  /// Returns all skills, loading and parsing them on first access.
  /// Cached after the first successful load — the markdown lives in
  /// the asset bundle and never changes at runtime.
  Future<List<Skill>> all() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    final inFlight = _loadFuture;
    if (inFlight != null) return inFlight;
    final future = _load();
    _loadFuture = future;
    return future;
  }

  /// Fetch a skill by id (the directory name). Returns null if not
  /// loaded or if the id doesn't match any built-in skill — the
  /// caller decides whether that's a hard error.
  Skill? byId(String id) {
    final cached = _cached;
    if (cached == null) return null;
    for (final skill in cached) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  /// Catalog block injected into Gemma 4's system prompt at chat
  /// creation. The shape is a numbered list of `id — description`
  /// lines so the model can:
  ///
  ///   1. Read the catalog once during prefill.
  ///   2. Decide which skill the user's situation matches.
  ///   3. Emit `skill_invoked: <id>` in the JSON output.
  ///
  /// Returns an empty string if the registry hasn't been loaded yet —
  /// callers should `await load()` before building the prompt.
  String buildCatalogPrompt() {
    final cached = _cached;
    if (cached == null || cached.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('## Available skills');
    buf.writeln(
      'You can invoke any skill below by setting `skill_invoked` in '
      'your JSON output. Pick the single best match for the user\'s '
      'situation. If nothing fits, set `skill_invoked: null` and '
      'answer in plain language.',
    );
    buf.writeln();
    for (final skill in cached) {
      buf.writeln('* `${skill.id}` — ${_oneLine(skill.description)}');
    }
    return buf.toString();
  }

  /// Single-line list of skill ids — used when the system-prompt
  /// budget is tight. Drops every description except the id, leaving
  /// the model with a discoverable vocabulary but no per-skill prose.
  /// Each id is a contract the agent already knows how to invoke
  /// because the matching SKILL.md was tested by the catalog author.
  String buildSkillsOneLiner() {
    final cached = _cached;
    if (cached == null || cached.isEmpty) return '';
    final ids = cached.map((s) => s.id).join(', ');
    return 'Skills available: $ids.';
  }

  /// Force load now (eg. at app boot) so the catalog is ready before
  /// the user opens the assistant. Safe to call multiple times.
  Future<void> load() async {
    await all();
  }

  Future<List<Skill>> _load() async {
    final skills = <Skill>[];
    for (final id in _skillIds) {
      try {
        final raw = await rootBundle.loadString(
          'assets/skills/$id/SKILL.md',
        );
        skills.add(_parseSkill(id, raw));
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[SkillsRegistry] failed to load skill "$id": $e (skipping)',
          );
        }
      }
    }
    _cached = List.unmodifiable(skills);
    return _cached!;
  }

  Skill _parseSkill(String id, String raw) {
    final parsed = _splitFrontmatter(raw);
    final frontmatter = parsed.frontmatter;
    final body = parsed.body;

    String? name;
    String? description;
    if (frontmatter != null && frontmatter.isNotEmpty) {
      try {
        final loaded = loadYaml(frontmatter);
        if (loaded is YamlMap) {
          final n = loaded['name'];
          final d = loaded['description'];
          if (n is String) name = n.trim();
          if (d is String) description = _normalizeWhitespace(d);
        }
      } on YamlException catch (e) {
        if (kDebugMode) {
          debugPrint('[SkillsRegistry] bad YAML in $id: $e');
        }
      }
    }
    return Skill(
      id: id,
      name: name ?? id,
      description: description ?? '',
      body: body.trim(),
    );
  }

  static _Frontmatter _splitFrontmatter(String raw) {
    // YAML frontmatter is fenced by `---` lines at the top of the
    // file. If the first non-empty line isn't `---`, the whole file
    // is body and we have no frontmatter.
    final normalized = raw.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---')) {
      return _Frontmatter(frontmatter: null, body: normalized);
    }
    // Find the closing `---` after the opening one.
    final closingIdx = normalized.indexOf('\n---', 3);
    if (closingIdx < 0) {
      return _Frontmatter(frontmatter: null, body: normalized);
    }
    final frontmatter = normalized.substring(3, closingIdx).trim();
    // Body starts after `\n---` and an optional trailing newline.
    var bodyStart = closingIdx + 4;
    if (bodyStart < normalized.length && normalized[bodyStart] == '\n') {
      bodyStart += 1;
    }
    final body = bodyStart >= normalized.length
        ? ''
        : normalized.substring(bodyStart);
    return _Frontmatter(frontmatter: frontmatter, body: body);
  }

  static String _normalizeWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _oneLine(String s) => _normalizeWhitespace(s);
}

@immutable
class _Frontmatter {
  const _Frontmatter({required this.frontmatter, required this.body});
  final String? frontmatter;
  final String body;
}
