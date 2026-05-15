import 'package:flutter/foundation.dart';

import 'place.dart';

/// Arguments emitted by Gemma 4 via the `render_map_view` native tool call.
/// Mirrors the find-nearby-places skill's intent: a closed-vocabulary list
/// of categories + a search radius + a short spoken summary the TTS layer
/// reads out while the inline map mounts.
///
/// Construction is tolerant — invalid category strings are dropped, the
/// radius clamps to the [PlaceCategory.defaultRadiusKm] of the widest
/// requested category, and an empty result falls back to the safe default
/// (shelter + hospital + water) so the model never produces a no-op call.
@immutable
class MapViewQuery {
  const MapViewQuery({
    required this.categories,
    required this.radiusKm,
    required this.spokenSummary,
  });

  final List<PlaceCategory> categories;
  final double radiusKm;
  final String spokenSummary;

  static const List<PlaceCategory> _defaultCategories = [
    PlaceCategory.shelter,
    PlaceCategory.hospital,
    PlaceCategory.waterPoint,
  ];

  /// Build from the model's tool-call args. The Gemma 4 SDK delivers args
  /// as `Map<String, dynamic>`; values may arrive as `List<dynamic>`,
  /// `String`, or even nested JSON strings. We coerce defensively.
  factory MapViewQuery.fromArgs(Map<String, dynamic> args) {
    final rawCategories = args['categories'];
    final categories = <PlaceCategory>[];
    if (rawCategories is List) {
      for (final raw in rawCategories) {
        final cat = PlaceCategory.fromWire(raw?.toString());
        if (cat != null) categories.add(cat);
      }
    } else if (rawCategories is String && rawCategories.isNotEmpty) {
      for (final token in rawCategories.split(RegExp(r'[,\s]+'))) {
        final cat = PlaceCategory.fromWire(token);
        if (cat != null) categories.add(cat);
      }
    }
    final effectiveCategories =
        categories.isEmpty ? _defaultCategories : categories;

    final rawRadius = args['radius_km'];
    double? radius;
    if (rawRadius is num) {
      radius = rawRadius.toDouble();
    } else if (rawRadius is String) {
      radius = double.tryParse(rawRadius);
    }
    final fallbackRadius = effectiveCategories
        .map((c) => c.defaultRadiusKm)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final double clampedRadius =
        (radius == null || radius <= 0 || radius > 50)
            ? (fallbackRadius == 0 ? 5.0 : fallbackRadius)
            : radius;

    final spoken = (args['spoken_summary'] as String?)?.trim() ??
        (args['summary'] as String?)?.trim() ??
        '';

    return MapViewQuery(
      categories: List.unmodifiable(effectiveCategories),
      radiusKm: clampedRadius,
      spokenSummary: spoken,
    );
  }

  @override
  String toString() => 'MapViewQuery(categories: '
      '${categories.map((c) => c.wireName).join(",")}, '
      'radiusKm: $radiusKm, spoken: ${spokenSummary.length}c)';
}

/// Sealed event surface for the chat-with-tools stream. The LLM service
/// merges Gemma's `Stream<ModelResponse>` into this so callers don't have
/// to reach into flutter_gemma internals.
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// Plain text chunk — drives the existing sentence-flush + TTS pipeline.
final class ChatTextChunk extends ChatStreamEvent {
  const ChatTextChunk(this.token);
  final String token;
}

/// Gemma asked us to render the find-nearby-places map. Cubit runs the
/// places query and attaches the result to the current [ConversationTurn].
final class ChatMapCall extends ChatStreamEvent {
  const ChatMapCall(this.query);
  final MapViewQuery query;
}
