import 'dart:convert';

import 'package:JsxposedX/features/ai/domain/models/ai_tool_call.dart';

/// Result of parsing one external-AI answer.
class ParsedManualResponse {
  const ParsedManualResponse({
    required this.toolCalls,
    this.narrative = '',
    this.warnings = const [],
  });

  final List<AiToolCall> toolCalls;

  /// Any human-readable explanation that came alongside the tool calls
  /// (kept so the app can surface what the AI intended).
  final String narrative;

  final List<String> warnings;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Parses an arbitrary external-AI answer into a list of tool calls.
///
/// Different free AI services (ChatGPT, Claude, 文心一言, ...) format function
/// calls differently. This parser is deliberately tolerant and tries, in
/// order:
///   1. OpenAI / Anthropic function-calling JSON (`tool_calls` array).
///   2. A raw JSON array of `{name, arguments}` objects.
///   3. A JSON object containing a `tool`/`tool_call`/`function` key.
///   4. Markdown fenced ```json blocks.
///   5. XML-ish `<tool_call><name>..</name><arguments>..</arguments></tool_call>`.
///   6. Line-oriented `TOOL: name ARGS: {...}` / `[tool]name[/tool]` syntax.
///   7. A plain scan: any line mentioning a known tool name with JSON args.
///
/// Unknown tool names are dropped with a warning instead of failing hard,
/// so a partially-usable answer never blocks the user.
class ManualResponseParser {
  const ManualResponseParser(this.knownToolNames);

  /// Valid tool names (from the environment's tool spec).
  final Set<String> knownToolNames;

  ParsedManualResponse parse(String rawResponse) {
    final warnings = <String>[];
    if (rawResponse.trim().isEmpty) {
      return ParsedManualResponse(
        toolCalls: const [],
        warnings: const ['AI 返回为空'],
      );
    }

    // Try the most structured candidates first.
    final fromStructured = _tryStructured(rawResponse, warnings);
    if (fromStructured.isNotEmpty) {
      final cleaned = _filterUnknown(fromStructured, warnings);
      return ParsedManualResponse(
        toolCalls: cleaned,
        narrative: _extractNarrative(rawResponse),
        warnings: warnings,
      );
    }

    // Fall back to XML-ish tags.
    final fromXml = _tryXml(rawResponse, warnings);
    if (fromXml.isNotEmpty) {
      return ParsedManualResponse(
        toolCalls: _filterUnknown(fromXml, warnings),
        narrative: _extractNarrative(rawResponse),
        warnings: warnings,
      );
    }

    // Fall back to line-oriented syntax.
    final fromLines = _tryLineSyntax(rawResponse, warnings);
    if (fromLines.isNotEmpty) {
      return ParsedManualResponse(
        toolCalls: _filterUnknown(fromLines, warnings),
        narrative: _extractNarrative(rawResponse),
        warnings: warnings,
      );
    }

    // Last resort: greedy scan for known tool names + JSON args.
    final fromScan = _scan(rawResponse, warnings);
    return ParsedManualResponse(
      toolCalls: _filterUnknown(fromScan, warnings),
      narrative: _extractNarrative(rawResponse),
      warnings: warnings,
    );
  }

  // ── strategy 1: structured JSON (tool_calls / raw array / tool key) ──

  List<AiToolCall> _tryStructured(String raw, List<String> warnings) {
    for (final candidate in _jsonCandidates(raw)) {
      final decoded = _decodeJson(candidate);
      if (decoded == null) {
        continue;
      }
      final parsed = _parseDecoded(decoded);
      if (parsed != null) {
        return parsed;
      }
    }
    return const [];
  }

  Iterable<String> _jsonCandidates(String raw) sync* {
    // 1. The whole trimmed text.
    yield raw.trim();

    // 2. Every ```json / ```  fence.
    final fenceRe = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
    for (final m in fenceRe.allMatches(raw)) {
      yield m.group(1)!.trim();
    }

    // 3. Look for a `{` ... `}` span that contains "tool_calls".
    final braceStart = raw.indexOf('{');
    final braceEnd = raw.lastIndexOf('}');
    if (braceStart >= 0 && braceEnd > braceStart) {
      yield raw.substring(braceStart, braceEnd + 1).trim();
    }
  }

  dynamic _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  List<AiToolCall>? _parseDecoded(dynamic decoded) {
    if (decoded is List) {
      final calls = <AiToolCall>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final call = _fromMap(item);
          if (call != null) calls.add(call);
        }
      }
      return calls;
    }

    if (decoded is Map<String, dynamic>) {
      // OpenAI/Anthropic style: {"tool_calls":[...]} or {"output":[{"type":"function_call"...}]}
      final toolCalls = decoded['tool_calls'] ??
          decoded['toolCalls'] ??
          decoded['function_calls'] ??
          decoded['calls'];
      if (toolCalls is List) {
        final calls = <AiToolCall>[];
        for (final item in toolCalls) {
          if (item is Map<String, dynamic>) {
            final call = _fromMap(item);
            if (call != null) calls.add(call);
          }
        }
        return calls;
      }
      // Anthropic Responses "output" array with function_call items.
      final output = decoded['output'];
      if (output is List) {
        final calls = <AiToolCall>[];
        for (final item in output) {
          if (item is Map<String, dynamic> &&
              item['type'] == 'function_call') {
            final name = item['name'] as String?;
            final args = item['arguments'];
            if (name != null && args is Map) {
              calls.add(
                AiToolCall(
                  id: item['id'] as String? ?? '',
                  name: name,
                  arguments: Map<String, dynamic>.from(args),
                ),
              );
            }
          }
        }
        return calls;
      }
      // A single tool object at top level.
      final single = _fromMap(decoded);
      if (single != null) {
        return [single];
      }
    }
    return null;
  }

  AiToolCall? _fromMap(Map<String, dynamic> map) {
    // Nested function (OpenAI).
    final function = map['function'];
    if (function is Map<String, dynamic>) {
      final name = function['name'] as String? ?? '';
      final args = function['arguments'];
      return AiToolCall(
        id: map['id'] as String? ?? '',
        name: name,
        arguments: _coerceArgs(args),
      );
    }

    // Direct keys.
    final name = (map['name'] as String?) ??
        (map['tool_name'] as String?) ??
        (map['tool'] as String?) ??
        (map['tool_call'] is Map ? (map['tool_call'] as Map)['name'] as String? : null) ??
        '';
    if (name.isEmpty) {
      return null;
    }

    final args = map['arguments'] ??
        map['args'] ??
        map['parameters'] ??
        map['input'] ??
        map['params'];
    return AiToolCall(id: map['id'] as String? ?? '', name: name, arguments: _coerceArgs(args));
  }

  Map<String, dynamic> _coerceArgs(dynamic args) {
    if (args is Map) {
      return Map<String, dynamic>.from(args);
    }
    if (args is String) {
      try {
        final decoded = jsonDecode(args);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  // ── strategy 2: XML-ish tags ──

  List<AiToolCall> _tryXml(String raw, List<String> warnings) {
    final tagRe = RegExp(
      r'<tool_call>\s*<name>\s*([^<]+?)\s*</name>\s*(?:<arguments>\s*([\s\S]*?)\s*</arguments>)?\s*</tool_call>',
      caseSensitive: false,
    );
    final calls = <AiToolCall>[];
    for (final m in tagRe.allMatches(raw)) {
      final name = m.group(1)!.trim();
      final args = _coerceArgs(m.group(2));
      calls.add(AiToolCall(id: '', name: name, arguments: args));
    }
    return calls;
  }

  // ── strategy 3: line-oriented syntax ──

  List<AiToolCall> _tryLineSyntax(String raw, List<String> warnings) {
    final calls = <AiToolCall>[];
    final lineRe = RegExp(
      r'^(?:TOOL|CALL|工具)\s*[:：]\s*([\w.]+)\s*(?:ARGS|args|参数)\s*[:：]\s*(\{.*\})$',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in lineRe.allMatches(raw)) {
      final name = m.group(1)!.trim();
      final args = _coerceArgs(m.group(2));
      calls.add(AiToolCall(id: '', name: name, arguments: args));
    }

    // [tool]name[/tool] style with optional [args]{...}[/args]
    if (calls.isEmpty) {
      final btRe = RegExp(
        r'\[tool\]\s*([\w.]+?)\s*\[/tool\](?:\s*\[args\]\s*(\{.*?\})\s*\[/args\])?',
        caseSensitive: false,
      );
      for (final m in btRe.allMatches(raw)) {
        calls.add(
          AiToolCall(
            id: '',
            name: m.group(1)!.trim(),
            arguments: _coerceArgs(m.group(2)),
          ),
        );
      }
    }
    return calls;
  }

  // ── strategy 4: greedy scan ──

  List<AiToolCall> _scan(String raw, List<String> warnings) {
    final calls = <AiToolCall>[];
    for (final name in knownToolNames) {
      final idx = raw.indexOf(name);
      if (idx < 0) {
        continue;
      }
      final tail = raw.substring(idx + name.length);
      final braceStart = tail.indexOf('{');
      final braceEnd = tail.lastIndexOf('}');
      Map<String, dynamic> args = {};
      if (braceStart >= 0 && braceEnd > braceStart) {
        args = _coerceArgs(tail.substring(braceStart, braceEnd + 1));
      }
      calls.add(AiToolCall(id: '', name: name, arguments: args));
    }
    return calls;
  }

  List<AiToolCall> _filterUnknown(
    List<AiToolCall> calls,
    List<String> warnings,
  ) {
    final result = <AiToolCall>[];
    for (final call in calls) {
      if (knownToolNames.contains(call.name)) {
        result.add(call);
      } else {
        warnings.add('忽略未知工具: ${call.name}');
      }
    }
    return result;
  }

  String _extractNarrative(String raw) {
    // Strip fences & structured tags to leave rough prose.
    var text = raw.replaceAll(RegExp(r'```(?:json)?\s*[\s\S]*?```'), ' ');
    text = text.replaceAll(RegExp(r'<tool_call>[\s\S]*?</tool_call>'), ' ');
    return text.trim();
  }
}
