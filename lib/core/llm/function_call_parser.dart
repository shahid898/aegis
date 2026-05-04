import 'dart:convert';

import 'function_call.dart';

/// Parses FunctionGemma-style `<start_function_call>...<end_function_call>`
/// blocks out of an LLM response.
///
/// The protocol the model is prompted to emit looks like:
///
/// ```
/// <start_function_call>
/// {"name": "dispatch_local_alarm",
///  "arguments": {"severity": "critical", "reason": "Tsunami"},
///  "rationale": "IMD short-code + tsunami keyword"}
/// <end_function_call>
/// ```
///
/// Multiple blocks are allowed and are returned in document order. Any
/// prose between blocks is ignored. The parser is intentionally lenient
/// because on-device models drop closing fences, double-encode JSON, or
/// emit single quotes — failing the whole pipeline because of a trailing
/// brace would be the opposite of helpful in an emergency. We log and
/// skip malformed blocks instead.
class FunctionCallParser {
  const FunctionCallParser({this.allowList = defaultFunctionDefinitions});

  /// Optional whitelist of allowed actions. Blocks naming an action not in
  /// this list are dropped — defends against the model hallucinating a
  /// novel function name. Pass `const []` to disable filtering entirely
  /// (useful only in tests).
  final List<FunctionDefinition> allowList;

  static final RegExp _blockPattern = RegExp(
    r'<start_function_call>(.*?)<end_function_call>',
    dotAll: true,
  );
  static final RegExp _nativeHeader = RegExp(r'call:(\w+)\{', dotAll: true);
  static final RegExp _nativeArg = RegExp(
    r'(\w+):<escape>(.*?)<escape>',
    dotAll: true,
  );

  /// Pull every well-formed function call out of [text]. Returns an empty
  /// list when none are found — callers treat that as "model produced no
  /// actionable plan" and can fall back to the regex classifier alone.
  List<FunctionCall> parse(String text) {
    if (text.isEmpty) return const [];
    final matches = _blockPattern.allMatches(text);

    final allowed = allowList.isEmpty
        ? null
        : allowList.map((d) => d.action).toSet();

    final out = <FunctionCall>[];
    if (matches.isNotEmpty) {
      for (final m in matches) {
        final body = m.group(1);
        if (body == null) continue;
        final call = _decodeBlock(body);
        if (call == null) continue;
        if (allowed != null && !allowed.contains(call.action)) continue;
        out.add(call);
      }
      return List.unmodifiable(out);
    }

    // FunctionGemma often gets cut by stop tokens before `<end_function_call>`.
    // Accept a single truncated block when at least `<start_function_call>`
    // and a parseable `call:<name>{...` header are present.
    final startIdx = text.indexOf('<start_function_call>');
    if (startIdx >= 0) {
      var body = text.substring(startIdx + '<start_function_call>'.length);
      final endIdx = body.indexOf('<end_function_call>');
      if (endIdx >= 0) body = body.substring(0, endIdx);
      final call = _decodeBlock(body.trim());
      if (call != null &&
          (allowed == null || allowed.contains(call.action))) {
        out.add(call);
      }
    }
    return List.unmodifiable(out);
  }

  FunctionCall? _decodeBlock(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final native = _decodeNativeBlock(trimmed);
    if (native != null) return native;

    final jsonText = _extractFirstJsonObject(trimmed);
    if (jsonText == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final name = decoded['name'];
    if (name is! String) return null;

    final action = FunctionRouteAction.fromWire(name);
    if (action == null) return null;

    final argsRaw = decoded['arguments'];
    final arguments = _coerceArgs(argsRaw);

    final rationaleRaw = decoded['rationale'];
    final rationale = rationaleRaw is String ? rationaleRaw : null;

    return FunctionCall(
      action: action,
      arguments: arguments,
      rationale: rationale,
    );
  }

  FunctionCall? _decodeNativeBlock(String raw) {
    final header = _nativeHeader.firstMatch(raw);
    if (header == null) return null;
    final name = header.group(1);
    final action = FunctionRouteAction.fromWire(name);
    if (action == null) return null;

    final args = <String, dynamic>{};
    for (final m in _nativeArg.allMatches(raw)) {
      final key = m.group(1);
      final value = m.group(2);
      if (key == null || value == null) continue;
      args[key] = value;
    }

    // Tolerate truncated `<escape>` values at end-of-generation.
    if (args.isEmpty) {
      final truncatedArg = RegExp(r'(\w+):<escape>([^<\n\r]+)', dotAll: true)
          .firstMatch(raw);
      if (truncatedArg != null) {
        final key = truncatedArg.group(1);
        final value = truncatedArg.group(2);
        if (key != null && value != null) {
          args[key] = value.trim();
        }
      }
    }
    return FunctionCall(action: action, arguments: args, rationale: null);
  }

  /// Some on-device runs ship `arguments` as a JSON-encoded string instead
  /// of an inline object (a known Gemma 270M quirk). Be tolerant: try to
  /// decode strings, otherwise fall back to an empty map.
  Map<String, dynamic> _coerceArgs(Object? raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } on FormatException {
        // fall through to empty
      }
    }
    return const <String, dynamic>{};
  }

  /// Walks [text] and returns the substring spanning the first balanced
  /// JSON object it finds, or null if no object can be located. Strings
  /// (including escaped quotes) are honoured so braces inside string
  /// literals don't fool the brace counter.
  static String? _extractFirstJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }
}
