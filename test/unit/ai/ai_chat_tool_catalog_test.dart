import 'package:JsxposedX/core/enums/ai_api_type.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_chat_tool_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final defs = [
    AiToolDefinition(
      name: 'get_manifest',
      description: 'd',
      parameters: ToolParametersBuilder.empty(),
    ),
    AiToolDefinition(
      name: 'search_classes',
      description: 's',
      parameters: (ToolParametersBuilder()
            ..addString('keyword', 'k', required: true))
          .build(),
    ),
  ];

  final catalog = AiChatToolCatalog(definitions: defs);

  test('builds OpenAI tools JSON for openai api type', () {
    final tools = catalog.buildToolsJson(apiType: AiApiType.openai);
    expect(tools, hasLength(2));
    expect(tools[0]['type'], 'function');
    expect(tools[0]['function']['name'], 'get_manifest');
  });

  test('builds OpenAI tools JSON for openaiResponses api type', () {
    final tools = catalog.buildToolsJson(apiType: AiApiType.openaiResponses);
    expect(tools[0]['function']['name'], 'get_manifest');
  });

  test('builds Anthropic tools JSON for anthropic api type', () {
    final tools = catalog.buildToolsJson(apiType: AiApiType.anthropic);
    expect(tools[0]['name'], 'get_manifest');
    expect(tools[0]['description'], 'd');
    expect(tools[0]['input_schema'], isA<Map>());
  });
}
