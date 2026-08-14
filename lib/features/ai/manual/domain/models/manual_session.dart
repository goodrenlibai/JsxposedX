import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';

enum ManualMessageRole { user, assistantTool, toolResult }

/// A single message in the manual-send conversation, used both to build the
/// copyable prompt (context) and to render history.
class ManualMessage {
  const ManualMessage({
    required this.role,
    required this.content,
    this.toolName,
  });

  final ManualMessageRole role;
  final String content;
  final String? toolName;

  bool get isUser => role == ManualMessageRole.user;
  bool get isToolResult => role == ManualMessageRole.toolResult;
}

/// One completed manual-send round.
class ManualRound {
  const ManualRound({
    required this.userRequest,
    required this.prompt,
    required this.aiResponse,
    required this.toolCalls,
    required this.toolResults,
    required this.resultPrompt,
  });

  final String userRequest;

  /// The text the user was told to copy into the external AI.
  final String prompt;

  /// The answer the user pasted back.
  final String aiResponse;

  final List<AiToolCall> toolCalls;

  /// Tool call -> tool execution result strings.
  final List<ManualToolExecution> toolResults;

  /// The text the user copies back to the external AI to continue.
  final String resultPrompt;
}

class ManualToolExecution {
  const ManualToolExecution({required this.call, required this.content, required this.success});

  final AiToolCall call;
  final String content;
  final bool success;
}
