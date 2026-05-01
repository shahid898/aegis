import 'package:aegis/core/llm/function_call.dart';
import 'package:aegis/core/llm/function_call_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FunctionCallParser', () {
    const parser = FunctionCallParser();

    test('returns empty list for empty input', () {
      expect(parser.parse(''), isEmpty);
    });

    test('returns empty list when no fences are present', () {
      expect(parser.parse('I think we should evacuate.'), isEmpty);
    });

    test('parses a single well-formed block', () {
      const text = '''
<start_function_call>
{"name": "dispatch_local_alarm",
 "arguments": {"severity": "critical", "reason": "Tsunami"},
 "rationale": "IMD short-code + tsunami keyword"}
<end_function_call>
''';

      final calls = parser.parse(text);
      expect(calls, hasLength(1));
      expect(calls.first.action, FunctionRouteAction.dispatchLocalAlarm);
      expect(calls.first.arguments['severity'], 'critical');
      expect(calls.first.arguments['reason'], 'Tsunami');
      expect(calls.first.rationale, contains('IMD'));
    });

    test('parses multiple blocks in document order', () {
      const text = '''
<start_function_call>
{"name": "dispatch_local_alarm", "arguments": {"severity": "critical", "reason": "Tsunami"}}
<end_function_call>

some prose between blocks the model should not have emitted

<start_function_call>
{"name": "summarize_for_user", "arguments": {"language": "hi", "briefing": "evacuate now"}}
<end_function_call>
''';

      final calls = parser.parse(text);
      expect(calls.map((c) => c.action), [
        FunctionRouteAction.dispatchLocalAlarm,
        FunctionRouteAction.summarizeForUser,
      ]);
    });

    test('skips blocks that name an unknown action', () {
      const text = '''
<start_function_call>
{"name": "launch_missile", "arguments": {}}
<end_function_call>
<start_function_call>
{"name": "activate_mesh_relay", "arguments": {"ttl_minutes": 30}}
<end_function_call>
''';

      final calls = parser.parse(text);
      expect(calls, hasLength(1));
      expect(calls.first.action, FunctionRouteAction.activateMeshRelay);
      expect(calls.first.arguments['ttl_minutes'], 30);
    });

    test('skips malformed JSON without aborting the whole parse', () {
      const text = '''
<start_function_call>
{"name": "dispatch_local_alarm", "arguments": {"severity": "critical"
<end_function_call>
<start_function_call>
{"name": "request_clarification", "arguments": {"reason": "low confidence"}}
<end_function_call>
''';

      final calls = parser.parse(text);
      expect(calls, hasLength(1));
      expect(calls.first.action, FunctionRouteAction.requestClarification);
    });

    test('coerces stringified arguments back into a Map', () {
      const text = '''
<start_function_call>
{"name": "summarize_for_user",
 "arguments": "{\\"language\\": \\"th\\", \\"briefing\\": \\"hi\\"}"}
<end_function_call>
''';

      final calls = parser.parse(text);
      expect(calls, hasLength(1));
      expect(calls.first.arguments['language'], 'th');
      expect(calls.first.arguments['briefing'], 'hi');
    });

    test('returns empty arguments map when payload omits the field', () {
      const text = '''
<start_function_call>
{"name": "request_clarification"}
<end_function_call>
''';

      final calls = parser.parse(text);
      expect(calls, hasLength(1));
      expect(calls.first.arguments, isEmpty);
      expect(calls.first.action, FunctionRouteAction.requestClarification);
    });

    test('honours an explicit empty allow list (no filtering)', () {
      const permissive = FunctionCallParser(allowList: []);
      const text = '''
<start_function_call>
{"name": "dispatch_local_alarm", "arguments": {}}
<end_function_call>
''';

      final calls = permissive.parse(text);
      // Even with no allow list we still drop unknown action names because
      // [FunctionRouteAction.fromWire] returns null for them. A known
      // action passes through, demonstrating the "no filter" path works.
      expect(calls, hasLength(1));
      expect(calls.first.action, FunctionRouteAction.dispatchLocalAlarm);
    });

    test('handles braces inside string literals', () {
      const text = '''
<start_function_call>
{"name": "summarize_for_user",
 "arguments": {"briefing": "Use template {place}: evacuate {now}"}}
<end_function_call>
''';

      final calls = parser.parse(text);
      expect(calls, hasLength(1));
      expect(
        calls.first.arguments['briefing'],
        'Use template {place}: evacuate {now}',
      );
    });

    test('FunctionRouteAction.fromWire is case-insensitive', () {
      expect(
        FunctionRouteAction.fromWire('DISPATCH_LOCAL_ALARM'),
        FunctionRouteAction.dispatchLocalAlarm,
      );
      expect(FunctionRouteAction.fromWire('   summarize_for_user  '),
          FunctionRouteAction.summarizeForUser);
      expect(FunctionRouteAction.fromWire('not_a_thing'), isNull);
      expect(FunctionRouteAction.fromWire(null), isNull);
    });
  });
}
