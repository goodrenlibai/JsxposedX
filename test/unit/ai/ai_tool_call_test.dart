import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiToolCall.fromJson', () {
    test('OpenAI function-call shape', () {
      final call = AiToolCall.fromJson({
        'id': 'call_1',
        'function': {'name': 'get_manifest', 'arguments': '{}'},
      });
      expect(call.id, 'call_1');
      expect(call.name, 'get_manifest');
      expect(call.arguments, isEmpty);
    });

    test('arguments string is JSON-decoded', () {
      final call = AiToolCall.fromJson({
        'function': {'name': 'decompile_class', 'arguments': '{"className":"com.a.B"}'},
      });
      expect(call.arguments, {'className': 'com.a.B'});
    });

    test('arguments as a map is used directly', () {
      final call = AiToolCall.fromJson({
        'name': 'search_classes',
        'arguments': {'keyword': 'vip'},
      });
      expect(call.name, 'search_classes');
      expect(call.arguments, {'keyword': 'vip'});
    });

    test('malformed arguments JSON falls back to empty', () {
      final call = AiToolCall.fromJson({
        'function': {'name': 'x', 'arguments': '{not-json'},
      });
      expect(call.arguments, isEmpty);
    });

    test('missing name yields empty string', () {
      final call = AiToolCall.fromJson({'arguments': {}});
      expect(call.name, '');
    });
  });

  group('AiToolCall accessors', () {
    const call = AiToolCall(id: '1', name: 'n', arguments: {
      'count': '42',
      'items': ['a', 'b'],
      'flag': 'true',
    });

    test('getString returns value or default', () {
      expect(call.getString('count'), '42');
      expect(call.getString('missing'), '');
      expect(call.getString('missing', 'D'), 'D');
    });

    test('getInt parses value or default', () {
      expect(call.getInt('count'), 42);
      expect(call.getInt('flag'), 0); // 'true' is not an int
      expect(call.getInt('missing', 9), 9);
    });

    test('getStringList extracts list or empty', () {
      expect(call.getStringList('items'), ['a', 'b']);
      expect(call.getStringList('missing'), isEmpty);
    });
  });
}
