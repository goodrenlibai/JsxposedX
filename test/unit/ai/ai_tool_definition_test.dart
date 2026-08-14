import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const def = AiToolDefinition(
    name: 'decompile_class',
    description: '反编译指定类',
    parameters: {
      'type': 'object',
      'properties': {
        'className': {'type': 'string', 'description': '类名'},
      },
      'required': ['className'],
    },
  );

  test('toOpenAiToolJson emits OpenAI function format', () {
    final json = def.toOpenAiToolJson();
    expect(json['type'], 'function');
    expect(json['function']['name'], 'decompile_class');
    expect(json['function']['description'], '反编译指定类');
    expect(json['function']['parameters']['required'], ['className']);
  });

  test('toAnthropicToolJson emits Anthropic tool format', () {
    final json = def.toAnthropicToolJson();
    expect(json['name'], 'decompile_class');
    expect(json['description'], '反编译指定类');
    expect(json['input_schema']['properties'], isA<Map>());
  });

  group('ToolParametersBuilder', () {
    test('builds required array and properties', () {
      final params = (ToolParametersBuilder()
            ..addString('className', 'class', required: true)
            ..addInteger('depth', 'depth')
            ..addBoolean('force', 'force', required: true)
            ..addStringArray('keys', 'keys'))
          .build();
      expect(params['type'], 'object');
      expect(params['required'], ['className', 'force']);
      expect((params['properties'] as Map)['className']['type'], 'string');
      expect((params['properties'] as Map)['depth']['type'], 'integer');
      expect((params['properties'] as Map)['force']['type'], 'boolean');
      expect((params['properties'] as Map)['keys']['items']['type'], 'string');
    });

    test('addString supports enum values', () {
      final params = (ToolParametersBuilder()
            ..addString('mode', 'mode', enumValues: ['a', 'b']))
          .build();
      final mode = (params['properties'] as Map)['mode'] as Map;
      expect(mode['enum'], ['a', 'b']);
    });

    test('empty builder has no required props', () {
      final params = ToolParametersBuilder.empty();
      expect(params['type'], 'object');
      expect(params['required'], isEmpty);
    });
  });
}
