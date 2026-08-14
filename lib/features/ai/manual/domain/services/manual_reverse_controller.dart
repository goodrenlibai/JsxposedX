import 'package:JsxposedX/features/ai/domain/contracts/ai_chat_tool_executor_contract.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_definition.dart';
import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';
import 'package:JsxposedX/features/ai/manual/domain/models/manual_session.dart';
import 'package:JsxposedX/features/ai/manual/domain/services/manual_prompt_builder.dart';
import 'package:JsxposedX/features/ai/manual/domain/services/manual_response_parser.dart';
import 'package:flutter/foundation.dart';

/// Orchestrates the semi-automatic "manual send" reverse loop.
///
/// Lifecycle mirrors the required flow:
///   1. user enters a requirement -> [generatePrompt] returns a copyable prompt
///   2. user pastes the external-AI answer -> [execute] parses tool calls,
///      runs them with the real [AiChatToolExecutorContract], and returns a
///      copyable result block
///   3. user copies the result back to the AI, pastes the next answer ->
///      [execute] again; loop until the AI concludes
///   4. [restart] clears the session; [resetRound] starts a fresh sub-round
///
/// Context (previous rounds) is preserved and re-injected into every prompt,
/// so the loop behaves like the built-in auto mode without touching the
/// built-in API.
class ManualReverseController extends ChangeNotifier {
  ManualReverseController({
    required this.systemPrompt,
    required List<AiToolDefinition> toolDefinitions,
    required AiChatToolExecutorContract toolExecutor,
    bool isZh = true,
  }) : _builder = ManualPromptBuilder(isZh: isZh),
       _toolExecutor = toolExecutor,
       _toolDefinitions = List.unmodifiable(toolDefinitions),
       _parser = ManualResponseParser({
         for (final def in toolDefinitions) def.name,
       }) {
    _toolGuide = _builder.buildToolGuide(toolDefinitions);
  }

  final ManualPromptBuilder _builder;
  final AiChatToolExecutorContract _toolExecutor;
  final List<AiToolDefinition> _toolDefinitions;
  final ManualResponseParser _parser;
  final String systemPrompt;
  late final String _toolGuide;

  final List<ManualRound> _rounds = [];
  final List<ManualMessage> _history = [];

  ManualRound? _currentRound;
  bool _isExecuting = false;
  String? _lastError;

  List<ManualRound> get rounds => List.unmodifiable(_rounds);
  List<ManualMessage> get history => List.unmodifiable(_history);
  ManualRound? get currentRound => _currentRound;
  bool get isExecuting => _isExecuting;
  String? get lastError => _lastError;
  bool get hasSession => _currentRound != null || _rounds.isNotEmpty;

  /// Step 1: generate the copyable prompt for a (new or continued) requirement.
  String generatePrompt(String userRequest) {
    final request = userRequest.trim();
    final isFreshTask = _rounds.isEmpty && _currentRound == null;
    final prompt = isFreshTask
        ? _builder.buildInitialPrompt(
            systemPrompt: systemPrompt,
            toolGuide: _toolGuide,
            userRequest: request,
          )
        : _builder.buildContinuationPrompt(
            systemPrompt: systemPrompt,
            toolGuide: _toolGuide,
            history: _history,
            latestToolResults: request,
          );

    _currentRound = ManualRound(
      userRequest: request,
      prompt: prompt,
      aiResponse: '',
      toolCalls: const [],
      toolResults: const [],
      resultPrompt: '',
    );
    _history.add(
      ManualMessage(role: ManualMessageRole.user, content: request),
    );
    _lastError = null;
    notifyListeners();
    return prompt;
  }

  /// The prompt that should currently be copied by the user.
  String? get copyablePrompt => _currentRound?.prompt;

  /// Step 3: feed an external-AI answer back; parse + execute tools.
  Future<String> execute(String aiResponse) async {
    final round = _currentRound;
    if (round == null) {
      throw StateError('尚未生成提示词，请先输入需求');
    }
    if (_isExecuting) {
      throw StateError('正在执行中，请稍候');
    }

    _isExecuting = true;
    _lastError = null;
    notifyListeners();
    try {
      final parsed = _parser.parse(aiResponse);
      final updated = ManualRound(
        userRequest: round.userRequest,
        prompt: round.prompt,
        aiResponse: aiResponse,
        toolCalls: parsed.toolCalls,
        toolResults: const [],
        resultPrompt: '',
      );
      _currentRound = updated;

      if (!parsed.hasToolCalls) {
        // The AI concluded in plain text.
        _history.add(
          ManualMessage(role: ManualMessageRole.assistantTool, content: aiResponse),
        );
        _finalizeRound(updated);
        return aiResponse;
      }

      // Execute every tool call in order.
      final executions = <ManualToolExecution>[];
      for (final call in parsed.toolCalls) {
        final result = await _toolExecutor.execute(call);
        executions.add(
          ManualToolExecution(
            call: call,
            content: result.content,
            success: result.success,
          ),
        );
        _history.add(
          ManualMessage(
            role: ManualMessageRole.assistantTool,
            content: '${call.name}(${_formatArgs(call.arguments)})',
            toolName: call.name,
          ),
        );
        _history.add(
          ManualMessage(
            role: ManualMessageRole.toolResult,
            content: result.content,
            toolName: call.name,
          ),
        );
      }

      final resultPrompt = _builder.buildResultPrompt(executions: executions);
      _currentRound = ManualRound(
        userRequest: updated.userRequest,
        prompt: updated.prompt,
        aiResponse: aiResponse,
        toolCalls: parsed.toolCalls,
        toolResults: executions,
        resultPrompt: resultPrompt,
      );
      return resultPrompt;
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  void _finalizeRound(ManualRound round) {
    // Round with no further tool calls is complete.
    if (_currentRound != null && identical(_currentRound, round)) {
      // no-op; keep reference.
    }
    _rounds.add(round);
    // Keep the reference so copyableResult stays available.
    _currentRound = round;
  }

  /// The block to copy back to the external AI after the last [execute].
  String? get copyableResult {
    final round = _currentRound;
    if (round == null || round.resultPrompt.isEmpty) {
      return null;
    }
    return round.resultPrompt;
  }

  /// Start a brand-new sub-round (same session context).
  void resetRound() {
    if (_currentRound != null && _currentRound!.resultPrompt.isNotEmpty) {
      _rounds.add(_currentRound!);
    }
    _currentRound = null;
    notifyListeners();
  }

  /// Clear the whole session (context + history).
  void restart() {
    _rounds.clear();
    _history.clear();
    _currentRound = null;
    _lastError = null;
    _isExecuting = false;
    notifyListeners();
  }

  static String _formatArgs(Map<String, dynamic> args) {
    return args.entries.map((e) => '${e.key}=${e.value}').join(', ');
  }
}
