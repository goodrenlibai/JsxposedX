import 'package:JsxposedX/features/smali/domain/services/smali_patch_service.dart';

/// Parses the AI's smali modification plan (as output in the chat) into a list
/// of [SmaliModificationRequest]s.
///
/// The AI is instructed to output, per modified method:
///   ```
///   class: com.example.app.VipManager | method: isVip | file: smali/... | reason: ...
///   ```
///   followed by the COMPLETE smali of the method in ```smali ... ``` blocks
///   (first the before, then the after — the last smali block is treated as the
///   "modified" replacement).
///
/// The parser is tolerant: it scans the whole text, finds `class:` / `method:`
/// hints, and pairs them with smali code blocks. If a modification has no
/// `class:` hint it is skipped (with a note).
class SmaliPlanParser {
  const SmaliPlanParser._();

  static List<SmaliModificationRequest> parse(String text) {
    if (text.trim().isEmpty) return const [];

    final requests = <SmaliModificationRequest>[];
    final smaliBlocks = _extractSmaliBlocks(text);

    // Fall back: collect class/method hints anywhere in the text.
    final hints = _extractHints(text);

    if (hints.isEmpty) {
      // No structured hints: we can't safely map a method, so return nothing.
      return requests;
    }

    for (final hint in hints) {
      final className = hint['class'] ?? '';
      final methodName = hint['method'] ?? '';
      if (className.isEmpty || methodName.isEmpty) continue;

      // The AI is instructed to output the smali as "before" then "after", so
      // the LAST ```smali block is treated as the modified replacement.
      final modifiedSmali = smaliBlocks.isEmpty ? '' : smaliBlocks.last;

      if (modifiedSmali.isEmpty) continue;
      requests.add(
        SmaliModificationRequest(
          className: className,
          methodName: methodName,
          modifiedSmali: modifiedSmali,
        ),
      );
    }
    return requests;
  }

  static List<Map<String, String>> _extractHints(String text) {
    final result = <Map<String, String>>[];
    // Match lines like: class: com.x.Y | method: isVip
    final re = RegExp(
      r'class\s*[:：]\s*([\w.$]+)\s*[|\|，,]\s*method\s*[:：]\s*([\w$]+)',
      caseSensitive: false,
    );
    for (final m in re.allMatches(text)) {
      result.add({
        'class': m.group(1) ?? '',
        'method': m.group(2) ?? '',
      });
    }
    return result;
  }

  static List<String> _extractSmaliBlocks(String text) {
    final result = <String>[];
    final re = RegExp(
      r'```smali\s*\n?([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final m in re.allMatches(text)) {
      final block = m.group(1)?.trim();
      if (block != null && block.isNotEmpty) result.add(block);
    }
    return result;
  }
}
