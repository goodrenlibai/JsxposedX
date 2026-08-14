import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_executor_contract.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';
import 'package:JsxposedX/features/ai/manual/domain/services/manual_reverse_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExecutor implements AiChatToolExecutorContract {
  final calls = <String>[];
  @override
  Future<AiToolResult> execute(
    AiToolCall call, {
    AiToolProgressCallback? onProgress,
  }) async {
    calls.add(call.name);
    return AiToolResult.ok(call.id, call.name, 'result-for-${call.name}');
  }
}

ManualReverseController _controller(_FakeExecutor ex) {
  return ManualReverseController(
    systemPrompt: '你是逆向助手。',
    toolDefinitions: [
      AiToolDefinition(
        name: 'get_manifest',
        description: 'manifest',
        parameters: ToolParametersBuilder.empty(),
      ),
      AiToolDefinition(
        name: 'search_classes',
        description: 'search',
        parameters: (ToolParametersBuilder()
              ..addString('keyword', 'kw', required: true))
            .build(),
      ),
    ],
    toolExecutor: ex,
    isZh: true,
  );
}

void main() {
  test('generatePrompt returns a copyable prompt and records user request', () {
    final ex = _FakeExecutor();
    final ctrl = _controller(ex);
    final prompt = ctrl.generatePrompt('分析登录');
    expect(prompt, contains('分析登录'));
    expect(prompt, contains('你是逆向助手。'));
    expect(ctrl.copyablePrompt, prompt);
    expect(ctrl.hasSession, isTrue);
    expect(ctrl.history.where((m) => m.isUser), hasLength(1));
  });

  test('execute runs tools and returns a result prompt for continuation', () async {
    final ex = _FakeExecutor();
    final ctrl = _controller(ex);
    ctrl.generatePrompt('分析登录');

    final resultPrompt = await ctrl.execute(
      '{"tool_calls":['
      '{"function":{"name":"get_manifest","arguments":"{}"}},'
      '{"function":{"name":"search_classes","arguments":"{\\"keyword\\":\\"login\\"}"}}'
      ']}',
    );
    expect(ex.calls, ['get_manifest', 'search_classes']);
    expect(resultPrompt, contains('result-for-get_manifest'));
    expect(ctrl.copyableResult, resultPrompt);
  });

  test('execute with plain-text conclusion returns the text, no tools', () async {
    final ex = _FakeExecutor();
    final ctrl = _controller(ex);
    ctrl.generatePrompt('分析登录');

    final result = await ctrl.execute('分析完成，使用 AES。');
    expect(ex.calls, isEmpty);
    expect(result, contains('AES'));
    expect(ctrl.copyableResult, isNull); // concluded → no continuation block
  });

  test('resetRound clears the in-progress round but keeps context', () async {
    final ex = _FakeExecutor();
    final ctrl = _controller(ex);
    ctrl.generatePrompt('r1');
    await ctrl.execute('{"tool_calls":[{"function":{"name":"get_manifest","arguments":"{}"}}]}');
    expect(ctrl.copyableResult, isNotNull);

    ctrl.resetRound();
    expect(ctrl.copyableResult, isNull);
    // Context (history) is preserved for continuation.
    expect(ctrl.history, isNotEmpty);
  });

  test('restart clears the whole session', () async {
    final ex = _FakeExecutor();
    final ctrl = _controller(ex);
    ctrl.generatePrompt('r1');
    await ctrl.execute('{"tool_calls":[{"function":{"name":"get_manifest","arguments":"{}"}}]}');

    ctrl.restart();
    expect(ctrl.hasSession, isFalse);
    expect(ctrl.history, isEmpty);
    expect(ctrl.rounds, isEmpty);
  });

  test('execute before generating a prompt throws', () async {
    final ex = _FakeExecutor();
    final ctrl = _controller(ex);
    await expectLater(ctrl.execute('anything'), throwsStateError);
  });

  test('isExecuting reflects in-flight execution', () async {
    final ex = _FakeExecutor();
    final ctrl = _controller(ex);
    ctrl.generatePrompt('t');
    final future = ctrl.execute(
      '{"tool_calls":[{"function":{"name":"get_manifest","arguments":"{}"}}]}',
    );
    // After a microtask the executor should have started.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await future;
    expect(ctrl.isExecuting, isFalse);
  });
}
