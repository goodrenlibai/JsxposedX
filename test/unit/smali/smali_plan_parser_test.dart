import 'package:JsxposedX/features/smali/domain/services/smali_plan_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmaliPlanParser.parse', () {
    test('parses class/method hints with a smali block', () {
      const text = '''
分析完成。

```modify
class: com.example.app.VipManager | method: isVip | file: smali/com/example/app/VipManager.smali | reason: 返回 true
```

修改前 smali:
```smali
.method public isVip()Z
    .locals 1
    iget-boolean v0, p0, Lcom/example/app/VipManager;->isPremium:Z
    return v0
.end method
```

修改后 smali:
```smali
.method public isVip()Z
    .locals 1
    const/4 v0, 0x1
    return v0
.end method
```
''';
      final requests = SmaliPlanParser.parse(text);
      expect(requests, hasLength(1));
      expect(requests.first.className, 'com.example.app.VipManager');
      expect(requests.first.methodName, 'isVip');
      expect(requests.first.dexPath, 'classes.dex');
      // Uses the LAST smali block as the modified replacement.
      expect(requests.first.modifiedSmali, contains('const/4 v0, 0x1'));
      expect(requests.first.modifiedSmali, contains('.end method'));
    });

    test('returns empty for text without class/method hints', () {
      const text = '分析完成，登录使用 AES。';
      expect(SmaliPlanParser.parse(text), isEmpty);
    });

    test('returns empty for blank input', () {
      expect(SmaliPlanParser.parse(''), isEmpty);
      expect(SmaliPlanParser.parse('   '), isEmpty);
    });

    test('handles multiple method hints', () {
      const text = '''
```modify
class: a.b.C | method: one | file: x | reason: r1
```
```smali
.method one()V
  return-void
.end method
```
```modify
class: a.b.D | method: two | file: y | reason: r2
```
```smali
.method two()I
  const/4 v0, 0x2
  return v0
.end method
```
''';
      final requests = SmaliPlanParser.parse(text);
      expect(requests, hasLength(2));
      expect(requests.map((r) => r.className), containsAll(['a.b.C', 'a.b.D']));
      // Both share the last smali block (single replacement smali).
      for (final r in requests) {
        expect(r.modifiedSmali, isNotEmpty);
      }
    });

    test('skips hint without method name', () {
      const text = '''
class: com.example.app.VipManager | method: | file: x
```smali
.method x()V
.end method
```
''';
      expect(SmaliPlanParser.parse(text), isEmpty);
    });
  });
}
