import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/ai/manual/domain/models/manual_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManualMessage', () {
    test('role flags are correct', () {
      const user = ManualMessage(role: ManualMessageRole.user, content: 'hi');
      const tool = ManualMessage(role: ManualMessageRole.toolResult, content: 'r');
      expect(user.isUser, isTrue);
      expect(user.isToolResult, isFalse);
      expect(tool.isToolResult, isTrue);
      expect(tool.isUser, isFalse);
    });

    test('carries optional tool name', () {
      const msg = ManualMessage(
        role: ManualMessageRole.assistantTool,
        content: 'get_manifest',
        toolName: 'get_manifest',
      );
      expect(msg.toolName, 'get_manifest');
    });
  });

  group('ManualToolExecution', () {
    test('exposes success and content', () {
      const ex = ManualToolExecution(
        call: AiToolCall(id: '1', name: 'get_manifest', arguments: {}),
        content: 'manifest',
        success: true,
      );
      expect(ex.success, isTrue);
      expect(ex.content, 'manifest');
      expect(ex.call.name, 'get_manifest');
    });
  });

  group('ManualRound', () {
    test('holds all round fields', () {
      const round = ManualRound(
        userRequest: 'analyze',
        prompt: 'prompt',
        aiResponse: 'resp',
        toolCalls: [],
        toolResults: [],
        resultPrompt: 'result',
      );
      expect(round.userRequest, 'analyze');
      expect(round.prompt, 'prompt');
      expect(round.aiResponse, 'resp');
      expect(round.toolCalls, isEmpty);
      expect(round.toolResults, isEmpty);
      expect(round.resultPrompt, 'result');
    });
  });
}
