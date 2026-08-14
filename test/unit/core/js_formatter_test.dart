import 'package:JsxposedX/core/utils/js_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsFormatter operator spacing', () {
    test('binary + gets spaces', () {
      expect(JsFormatter.format('a+b'), 'a + b');
    });

    test('equality operator gets spaces', () {
      expect(JsFormatter.format('x==y'), 'x == y');
      expect(JsFormatter.format('x!==y'), 'x !== y');
    });

    test('assignment gets spaces', () {
      expect(JsFormatter.format('let i=0;'), 'let i = 0;');
    });

    test('arrow function operator spaced', () {
      expect(JsFormatter.format('(x)=>x+1'), '(x) => x + 1');
    });

    test('empty input returns empty', () {
      expect(JsFormatter.format(''), '');
      expect(JsFormatter.format('   '), '   ');
    });
  });

  group('JsFormatter structure', () {
    test('function body is indented', () {
      final out = JsFormatter.format('function f(){return 1;}');
      expect(out, contains('function f() {'));
      expect(out, contains('return 1;'));
      expect(out, contains('\n  return 1;'));
    });

    test('if/else chain stays together on one logical block', () {
      final out = JsFormatter.format('if(a){b();}else{c();}');
      // The formatter keeps else on the same line as the closing brace.
      expect(out, contains('if(a) {'));
      expect(out, contains('} else {'));
      expect(out, contains('b();'));
      expect(out, contains('c();'));
    });

    test('strings with operators inside are untouched', () {
      // The '==' inside the string literal must not be spaced.
      final out = JsFormatter.format("var s='a==b';");
      expect(out, contains("'a==b'"));
    });
  });
}
