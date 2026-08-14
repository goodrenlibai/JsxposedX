import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';
import 'package:JsxposedX/features/ai/manual/domain/models/manual_session.dart';
import 'package:JsxposedX/features/ai/manual/domain/services/manual_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final defs = [
    AiToolDefinition(
      name: 'get_manifest',
      description: '获取 Manifest',
      parameters: ToolParametersBuilder.empty(),
    ),
    AiToolDefinition(
      name: 'search_classes',
      description: '搜索类',
      parameters: (ToolParametersBuilder()
            ..addString('keyword', '关键词', required: true))
          .build(),
    ),
  ];

  final builder = ManualPromptBuilder(isZh: true);

  test('buildToolGuide lists tools and JSON format', () {
    final guide = builder.buildToolGuide(defs);
    expect(guide, contains('get_manifest'));
    expect(guide, contains('search_classes'));
    expect(guide, contains('tool_calls'));
    expect(guide, contains('必填: keyword'));
  });

  test('buildInitialPrompt includes system, tools and request', () {
    final guide = builder.buildToolGuide(defs);
    final prompt = builder.buildInitialPrompt(
      systemPrompt: '你是逆向助手。',
      toolGuide: guide,
      userRequest: '分析登录逻辑',
    );
    expect(prompt, contains('你是逆向助手。'));
    expect(prompt, contains('get_manifest'));
    expect(prompt, contains('分析登录逻辑'));
  });

  test('buildContinuationPrompt embeds history and latest results', () {
    final guide = builder.buildToolGuide(defs);
    final prompt = builder.buildContinuationPrompt(
      systemPrompt: 'sys',
      toolGuide: guide,
      history: const [
        ManualMessage(role: ManualMessageRole.user, content: '需求A'),
        ManualMessage(role: ManualMessageRole.toolResult, content: '结果B'),
      ],
      latestToolResults: '最新结果C',
    );
    expect(prompt, contains('需求A'));
    expect(prompt, contains('结果B'));
    expect(prompt, contains('最新结果C'));
  });

  test('buildResultPrompt formats executed tool outputs', () {
    final prompt = builder.buildResultPrompt(
      executions: const [
        ManualToolExecution(
          call: AiToolCall(id: '1', name: 'get_manifest', arguments: {}),
          content: 'manifest-content',
          success: true,
        ),
        ManualToolExecution(
          call: AiToolCall(id: '2', name: 'search_classes', arguments: {'keyword': 'x'}),
          content: 'error',
          success: false,
        ),
      ],
    );
    expect(prompt, contains('get_manifest'));
    expect(prompt, contains('manifest-content'));
    expect(prompt, contains('search_classes'));
    expect(prompt, contains('error'));
    expect(prompt, contains('ok'));
    expect(prompt, contains('tool='));
  });
}
