import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';
import 'package:JsxposedX/features/ai/manual/domain/models/manual_session.dart';

/// Builds the human-friendly, copyable prompt that the user pastes into an
/// external AI (ChatGPT, Claude, 文心一言, ...) and the follow-up prompt that
/// feeds the AI's tool results back for the next iteration.
class ManualPromptBuilder {
  ManualPromptBuilder({bool isZh = true}) : _isZh = isZh;

  final bool _isZh;

  /// Build the tools guide describing available tool calls + expected format.
  String buildToolGuide(List<AiToolDefinition> definitions) {
    final buf = StringBuffer();
    buf.writeln(
      _isZh
          ? '【可用工具】你可以调用以下工具来完成逆向分析。'
          : '[Available tools] You may call the following tools to complete the reverse analysis.',
    );
    for (final def in definitions) {
      final required = (def.parameters['required'] as List?)?.cast<String>() ??
          const <String>[];
      final requiredHint = required.isEmpty ? '' : ' (必填: ${required.join(', ')})';
      buf.writeln('- `$_wrapName(def.name)`: ${def.description}$requiredHint');
    }
    buf
      ..writeln()
      ..writeln(
        _isZh
            ? '请用严格 JSON 输出工具调用，格式如下（不要输出其他说明文字，除非有需要给用户的文字）：'
            : 'Output tool calls as strict JSON, in this format (do not add other prose unless you have a note for the user):',
      )
      ..writeln('```json')
      ..writeln('{"tool_calls":[{"id":"1","function":{"name":"TOOL_NAME","arguments":"{\\"key\\":\\"value\\"}"}}]}')
      ..writeln('```')
      ..writeln()
      ..writeln(
        _isZh
            ? '当任务完成时，请以纯文字总结结论即可（不要输出 tool_calls）。'
            : 'When the task is complete, just summarize your conclusions in plain text (no tool_calls).',
      );
    return buf.toString();
  }

  String _wrapName(String name) => name;

  /// Build the initial prompt for a brand-new manual-send round.
  String buildInitialPrompt({
    required String systemPrompt,
    required String toolGuide,
    required String userRequest,
  }) {
    final buf = StringBuffer();
    buf.writeln(systemPrompt.trim());
    buf
      ..writeln()
      ..writeln(toolGuide)
      ..writeln()
      ..writeln(_isZh ? '【本次需求】' : '[This request]')
      ..writeln(userRequest.trim());
    return buf.toString();
  }

  /// Build a follow-up prompt that includes the previous context plus the tool
  /// results the user just pasted back, asking the AI to continue.
  String buildContinuationPrompt({
    required String systemPrompt,
    required String toolGuide,
    required List<ManualMessage> history,
    required String latestToolResults,
  }) {
    final buf = StringBuffer();
    buf.writeln(systemPrompt.trim());
    buf
      ..writeln()
      ..writeln(toolGuide)
      ..writeln()
      ..writeln(_isZh ? '【上下文摘要】' : '[Context]');
    if (history.isEmpty) {
      buf.writeln(_isZh ? '（无）' : '(none)');
    } else {
      for (final msg in history) {
        switch (msg.role) {
          case ManualMessageRole.user:
            buf.writeln(_isZh ? '用户需求: ' : 'User: ');
            buf.writeln(msg.content);
          case ManualMessageRole.assistantTool:
            buf.writeln(_isZh ? '已执行工具: ' : 'Called tool: ');
            buf.writeln(msg.content);
          case ManualMessageRole.toolResult:
            buf.writeln(_isZh ? '工具结果: ' : 'Tool result: ');
            buf.writeln(msg.content);
        }
      }
    }
    buf
      ..writeln()
      ..writeln(_isZh ? '【最新的工具执行结果，请据此继续分析】' : '[Latest tool results - continue from here]')
      ..writeln(latestToolResults.trim());
    return buf.toString();
  }

  /// Build the copyable "result" block: the executed tool outputs that the
  /// user copies back into the external AI.
  String buildResultPrompt({
    required List<ManualToolExecution> executions,
  }) {
    final buf = StringBuffer();
    buf.writeln(_isZh ? '【工具执行结果】' : '[Tool execution results]');
    for (var i = 0; i < executions.length; i++) {
      final ex = executions[i];
      buf.writeln('--- result ${i + 1} · tool=${ex.call.name} · ${ex.success ? 'ok' : 'error'} ---');
      buf.writeln(ex.content);
    }
    buf.writeln();
    buf.writeln(
      _isZh
          ? '请基于以上结果继续分析，若需要可继续输出 tool_calls，否则给出结论。'
          : 'Continue the analysis based on the above results. Output tool_calls if more tools are needed, otherwise give your conclusion.',
    );
    return buf.toString();
  }
}
