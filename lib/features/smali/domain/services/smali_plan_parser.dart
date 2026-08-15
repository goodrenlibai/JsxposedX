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

/// Parses the AI's answer following the fixed "task completion protocol":
///
///   - Completion marker: `[ANALYSIS_COMPLETE]` → [SmaliPlanParseResult.isAnalysisComplete]
///   - Each modification block:
///     ```
///     [SMALI_PLAN]
///     class: com.example.app.VipManager
///     method: isVip
///     ```smali
///     ... complete modified smali ...
///     ```
///     [SMALI_PLAN_END]
///     ```
///
/// The parser is tolerant to spacing/case and also keeps a fallback that scans
/// for `class:`/`method:` hints + smali blocks when the strict protocol is not
/// followed, so the one-click button still works on loosely-formatted output.
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

    final isComplete = _hasMarker(text, completeMarker);
    final mods = _parsePlanBlocks(text);

    // Fallback: if not complete via marker but a strict plan block exists,
    // treat it as complete (a plan implies analysis finished).
    final effectiveComplete = isComplete || mods.isNotEmpty;

    if (!effectiveComplete) {
      return const SmaliPlanParseResult(
        isAnalysisComplete: false,
        modifications: [],
      );
    }

    // If strict blocks produced nothing, fall back to hint-based parsing.
    final finalMods = mods.isNotEmpty ? mods : _fallbackParse(text);

    return SmaliPlanParseResult(
      isAnalysisComplete: effectiveComplete,
      modifications: finalMods,
    );
  }

  static bool _hasMarker(String text, String marker) {
    return text.toLowerCase().contains(marker.toLowerCase());
  }

  /// Parses `[SMALI_PLAN] ... [SMALI_PLAN_END]` blocks.
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

    // Extract the ```smali ... ``` block inside.
    final smaliRe = RegExp(r'```smali\s*\n?([\s\S]*?)```', caseSensitive: false);
    final smaliMatch = smaliRe.firstMatch(block);
    if (smaliMatch != null) smali = smaliMatch.group(1)?.trim() ?? '';

    if (className == null ||
        className.isEmpty ||
        methodName == null ||
        methodName.isEmpty) {
      return null;
    }
    if (smali.isEmpty) return null;
    return SmaliModificationRequest(
      className: className,
      methodName: methodName,
      modifiedSmali: smali,
    );
  }

  /// Fallback: scan the whole text for `class:`/`method:` hints + smali blocks.
  static List<SmaliModificationRequest> _fallbackParse(String text) {
    final result = <SmaliModificationRequest>[];
    final hints = <Map<String, String>>[];
    final hintRe = RegExp(
      r'class\s*[:：]\s*([\w.$]+)\s*[|\|，,]\s*method\s*[:：]\s*([\w$]+)',
      caseSensitive: false,
    );
    for (final m in hintRe.allMatches(text)) {
      hints.add({'class': m.group(1) ?? '', 'method': m.group(2) ?? ''});
    }
    if (hints.isEmpty) return result;

    final smaliBlocks = <String>[];
    final smaliRe = RegExp(r'```smali\s*\n?([\s\S]*?)```', caseSensitive: false);
    for (final m in smaliRe.allMatches(text)) {
      final b = m.group(1)?.trim();
      if (b != null && b.isNotEmpty) smaliBlocks.add(b);
    }
    if (smaliBlocks.isEmpty) return result;

    final lastSmali = smaliBlocks.last;
    for (final hint in hints) {
      final className = hint['class'] ?? '';
      final methodName = hint['method'] ?? '';
      if (className.isEmpty || methodName.isEmpty) continue;
      result.add(
        SmaliModificationRequest(
          className: className,
          methodName: methodName,
          modifiedSmali: lastSmali,
        ),
      );
    }
    return result;
  }
}
