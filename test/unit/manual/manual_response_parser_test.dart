import 'package:JsxposedX/features/ai/manual/domain/services/manual_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ManualResponseParser({
    'get_manifest',
    'decompile_class',
    'search_classes',
  });

  group('structured JSON formats', () {
    test('OpenAI tool_calls object', () {
      final r = parser.parse(
        '{"tool_calls":[{"id":"1","function":{"name":"get_manifest","arguments":"{}"}}]}',
      );
      expect(r.hasToolCalls, isTrue);
      expect(r.toolCalls.single.name, 'get_manifest');
      expect(r.toolCalls.single.arguments, isEmpty);
    });

    test('raw JSON array of tool objects', () {
      final r = parser.parse(
        '[{"name":"search_classes","arguments":{"keyword":"vip"}}]',
      );
      expect(r.toolCalls.single.name, 'search_classes');
      expect(r.toolCalls.single.arguments, {'keyword': 'vip'});
    });

    test('single tool object at top level', () {
      final r = parser.parse('{"name":"get_manifest","arguments":{}}');
      expect(r.toolCalls.single.name, 'get_manifest');
    });

    test('markdown-fenced json block', () {
      final r = parser.parse(
        '思考一下\n```json\n{"tool_calls":[{"function":{"name":"decompile_class","arguments":"{\\"className\\":\\"com.a.B\\"}"}}]}\n```\n',
      );
      expect(r.toolCalls.single.name, 'decompile_class');
      expect(r.toolCalls.single.arguments, {'className': 'com.a.B'});
    });
  });

  group('loose formats', () {
    test('XML-style tool_call', () {
      final r = parser.parse(
        '<tool_call><name>get_manifest</name><arguments>{"k":"v"}</arguments></tool_call>',
      );
      expect(r.toolCalls.single.name, 'get_manifest');
    });

    test('line-oriented TOOL syntax', () {
      final r = parser.parse('TOOL: search_classes ARGS: {"keyword":"pay"}');
      expect(r.toolCalls.single.name, 'search_classes');
      expect(r.toolCalls.single.arguments, {'keyword': 'pay'});
    });
  });

  group('unknown & empty', () {
    test('unknown tool is dropped with a warning', () {
      final r = parser.parse(
        '{"tool_calls":[{"function":{"name":"unknown_tool","arguments":"{}"}}]}',
      );
      expect(r.hasToolCalls, isFalse);
      expect(r.warnings.any((w) => w.contains('unknown_tool')), isTrue);
    });

    test('plain text conclusion → no tool calls', () {
      final r = parser.parse('分析完成，登录使用 AES-256。');
      expect(r.hasToolCalls, isFalse);
      expect(r.narrative, contains('登录'));
    });

    test('empty string → no tool calls', () {
      final r = parser.parse('');
      expect(r.hasToolCalls, isFalse);
      expect(r.warnings, isNotEmpty);
    });
  });

  group('multi-call answers', () {
    test('multiple tool_calls preserved in order', () {
      final r = parser.parse(
        '{"tool_calls":['
        '{"function":{"name":"get_manifest","arguments":"{}"}},'
        '{"function":{"name":"search_classes","arguments":"{\\"keyword\\":\\"encrypt\\"}"}}'
        ']}',
      );
      expect(r.toolCalls, hasLength(2));
      expect(r.toolCalls[0].name, 'get_manifest');
      expect(r.toolCalls[1].name, 'search_classes');
    });
  });
}
