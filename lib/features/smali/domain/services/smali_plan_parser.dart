import 'package:JsxposedX/features/smali/domain/services/smali_patch_service.dart';

/// Result of parsing the AI's answer for task-completion + smali plans.
class SmaliPlanParseResult {
  final bool isAnalysisComplete;

  /// Parsed smali modification requests (empty if none / not complete).
  final List<SmaliModificationRequest> modifications;

  const SmaliPlanParseResult({
    required this.isAnalysisComplete,
    required this.modifications,
  });

  bool get hasModifications => modifications.isNotEmpty;
}

/// Parses the AI's answer to detect whether the analysis is complete and to
/// extract smali modification plans.
///
/// The AI is instructed to follow a fixed "task completion protocol" that
/// emits `[ANALYSIS_COMPLETE]` and `[SMALI_PLAN] ... [SMALI_PLAN_END]` blocks.
/// However, real-world AI answers often come in a looser format, e.g.:
///
///   ```modify
///   class: com.example.app.VipManager | method: isVip()Z | file: ... | reason: ...
///   ```
///   修改前：
///   ```smali ...before...```
///   修改后：
///   ```smali ...after...```
///
/// This parser handles BOTH:
///   1. The strict protocol (`[ANALYSIS_COMPLETE]` + `[SMALI_PLAN]` blocks).
///   2. The loose format: `modify` blocks with `class:`/`method:` hints paired
///      with the following smali blocks (the LAST smali block after a hint is
///      treated as the "modified after" replacement).
///
/// Completion is detected when EITHER the `[ANALYSIS_COMPLETE]` marker is
/// present OR at least one valid smali modification block is parsed (a plan
/// implies the analysis finished).
class SmaliPlanParser {
  const SmaliPlanParser._();

  static const String completeMarker = '[ANALYSIS_COMPLETE]';
  static const String planStart = '[SMALI_PLAN]';
  static const String planEnd = '[SMALI_PLAN_END]';

  static SmaliPlanParseResult parse(String text) {
    if (text.trim().isEmpty) {
      return const SmaliPlanParseResult(
        isAnalysisComplete: false,
        modifications: [],
      );
    }

    final hasCompleteMarker = _hasMarker(text, completeMarker);

    // Strict protocol blocks first.
    final strictMods = _parsePlanBlocks(text);
    // Loose format fallback (also handles the strict blocks' smali).
    final looseMods = _parseLooseFormat(text);

    // Combine: prefer strict, but if strict is empty use loose.
    final finalMods = strictMods.isNotEmpty ? strictMods : looseMods;

    // Completion = explicit marker OR a valid plan exists.
    final isComplete = hasCompleteMarker || finalMods.isNotEmpty;

    return SmaliPlanParseResult(
      isAnalysisComplete: isComplete,
      modifications: finalMods,
    );
  }

  static bool _hasMarker(String text, String marker) {
    return text.toLowerCase().contains(marker.toLowerCase());
  }

  // ── Strict protocol: [SMALI_PLAN] ... [SMALI_PLAN_END] ────────────────
  static List<SmaliModificationRequest> _parsePlanBlocks(String text) {
    final result = <SmaliModificationRequest>[];
    final startRe = RegExp(RegExp.escape(planStart), caseSensitive: false);
    final endRe = RegExp(RegExp.escape(planEnd), caseSensitive: false);

    var searchFrom = 0;
    while (true) {
      final startMatch = startRe.firstMatch(text.substring(searchFrom));
      if (startMatch == null) break;
      final absStart = searchFrom + startMatch.start;
      final blockStart = absStart + startMatch.group(0)!.length;

      final remainder = text.substring(blockStart);
      final endMatch = endRe.firstMatch(remainder);
      final String block;
      if (endMatch == null) {
        block = remainder;
      } else {
        block = remainder.substring(0, endMatch.start);
      }

      final req = _parseBlock(block);
      if (req != null) result.add(req);
      searchFrom = absStart + startMatch.group(0)!.length + 1;
    }
    return result;
  }

  static SmaliModificationRequest? _parseBlock(String block) {
    String? className;
    String? methodName;
    String smali = '';

    for (final line in block.split('\n')) {
      final t = line.trim();
      final classMatch = RegExp(
        r'class\s*[:：]\s*([\w.$]+)',
        caseSensitive: false,
      ).firstMatch(t);
      if (classMatch != null) className = classMatch.group(1);
      final methodMatch = RegExp(
        r'method\s*[:：]\s*([\w$]+)',
        caseSensitive: false,
      ).firstMatch(t);
      if (methodMatch != null) methodName = methodMatch.group(1);
    }

    final smaliRe = RegExp(r'```smali\s*\n?([\s\S]*?)```', caseSensitive: false);
    final smaliMatch = smaliRe.firstMatch(block);
    if (smaliMatch != null) smali = smaliMatch.group(1)?.trim() ?? '';

    return _buildRequest(className, methodName, smali);
  }

  // ── Loose format: `modify` blocks + before/after smali blocks ─────────
  static List<SmaliModificationRequest> _parseLooseFormat(String text) {
    // 1. Find all `modify` blocks with class/method hints (position + values).
    final modifyHints = <({int index, String className, String methodName})>[];
    final modifyRe = RegExp(
      r'```modify\s*\n?([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final m in modifyRe.allMatches(text)) {
      final body = m.group(1) ?? '';
      final className = _extractClass(body);
      final methodName = _extractMethod(body);
      if (className == null || methodName == null) continue;
      modifyHints.add((index: m.start, className: className, methodName: methodName));
    }

    // 2. Find all smali blocks (position + content).
    final smaliBlocks = <({int index, String content})>[];
    final smaliRe = RegExp(r'```smali\s*\n?([\s\S]*?)```', caseSensitive: false);
    for (final m in smaliRe.allMatches(text)) {
      final c = m.group(1)?.trim();
      if (c != null && c.isNotEmpty) {
        smaliBlocks.add((index: m.start, content: c));
      }
    }

    if (modifyHints.isEmpty) return const [];

    final result = <SmaliModificationRequest>[];
    for (var h = 0; h < modifyHints.length; h++) {
      final hint = modifyHints[h];
      // The "after" smali is the LAST smali block that appears after this hint
      // but BEFORE the next hint (each modify section owns its smali blocks).
      final nextHintIndex = h + 1 < modifyHints.length
          ? modifyHints[h + 1].index
          : text.length;
      String? afterSmali;
      for (final s in smaliBlocks) {
        if (s.index > hint.index && s.index < nextHintIndex) {
          afterSmali = s.content; // keep last one within this section
        }
      }
      final req = _buildRequest(hint.className, hint.methodName, afterSmali);
      if (req != null) result.add(req);
    }
    return result;
  }

  static String? _extractClass(String body) {
    final re = RegExp(r'class\s*[:：]\s*([\w.$]+)', caseSensitive: false);
    final m = re.firstMatch(body);
    return m?.group(1);
  }

  static String? _extractMethod(String body) {
    // method: A()Z  → A
    final re = RegExp(r'method\s*[:：]\s*([\w$]+)', caseSensitive: false);
    final m = re.firstMatch(body);
    return m?.group(1);
  }

  static SmaliModificationRequest? _buildRequest(
    String? className,
    String? methodName,
    String? smali,
  ) {
    final c = className?.trim() ?? '';
    final m = methodName?.trim() ?? '';
    final s = smali?.trim() ?? '';
    if (c.isEmpty || m.isEmpty || s.isEmpty) return null;
    if (!s.contains('.method')) return null; // must be a real smali method body
    return SmaliModificationRequest(
      className: c,
      methodName: m,
      modifiedSmali: s,
    );
  }
}
