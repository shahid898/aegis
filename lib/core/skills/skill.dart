import 'package:flutter/foundation.dart';

/// One discoverable capability of the agent.
///
/// A [Skill] is the parsed form of a `SKILL.md` file: its YAML
/// frontmatter (`name`, `description`) plus the markdown body.
/// Frontmatter is what gets concatenated into Gemma 4's system prompt
/// at chat creation, so the model can pick the right skill without any
/// Dart-side dispatch. The markdown body is reserved for sub-skill
/// invocation (we look it up by id when the model emits
/// `skill_invoked: <id>`).
@immutable
class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
  });

  /// Stable, lowercase, hyphenated identifier — matches the directory
  /// name under `assets/skills/` and the value Gemma 4 emits in
  /// `skill_invoked`. Treat it as the contract between markdown and
  /// JSON.
  final String id;

  /// Human-readable name used by the model for self-narration in
  /// thinking traces. Usually identical to `id` modulo casing /
  /// punctuation.
  final String name;

  /// One-paragraph summary describing when this skill fires. This is
  /// the line the model reads to decide whether the skill is a fit —
  /// keep it action-oriented.
  final String description;

  /// Full markdown body (everything after the frontmatter). Used at
  /// invocation time to ground the model on detailed instructions
  /// rather than padding the system prompt with every skill body.
  final String body;

  @override
  String toString() => 'Skill($id)';
}
