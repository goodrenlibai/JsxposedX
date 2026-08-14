import 'package:JsxposedX/features/ai/domain/models/ai_thinking_markup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiThinkingMarkup.compose', () {
    test('wraps thinking when both present', () {
      final out = AiThinkingMarkup.compose(thinking: '思考', answer: '答案');
      expect(out, startsWith('<ai-thinking>\n思考\n</ai-thinking>'));
      expect(out, endsWith('答案'));
    });

    test('returns answer alone when thinking empty', () {
      expect(AiThinkingMarkup.compose(thinking: '  ', answer: '答案'), '答案');
    });

    test('returns thinking block alone when answer empty', () {
      final out = AiThinkingMarkup.compose(thinking: '思考', answer: '');
      expect(out, '<ai-thinking>\n思考\n</ai-thinking>');
    });
  });

  group('AiThinkingMarkup.split', () {
    test('splits thinking and answer', () {
      final parts = AiThinkingMarkup.split(
        '<ai-thinking>\n内\n</ai-thinking>\n\n回',
      );
      expect(parts.thinking, '内');
      expect(parts.answer, '回');
      expect(parts.hasThinking, isTrue);
    });

    test('no markup → whole content is answer', () {
      final parts = AiThinkingMarkup.split('plain text');
      expect(parts.thinking, '');
      expect(parts.answer, 'plain text');
      expect(parts.hasThinking, isFalse);
    });

    test('malformed (end before start) treated as plain', () {
      final parts = AiThinkingMarkup.split('x</ai-thinking><ai-thinking>y');
      expect(parts.answer, contains('x'));
    });
  });

  test('AiThinkingMarkup.strip removes thinking block', () {
    expect(
      AiThinkingMarkup.strip('<ai-thinking>\n内\n</ai-thinking>\n\n答案'),
      '答案',
    );
  });
}
