import 'package:JsxposedX/features/smali/domain/services/smali_plan_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmaliPlanParser completion detection', () {
    test('detects ANALYSIS_COMPLETE marker', () {
      final r = SmaliPlanParser.parse('分析完成\n[ANALYSIS_COMPLETE]');
      expect(r.isAnalysisComplete, isTrue);
    });

    test('no completion when AI is still working (tool_calls only)', () {
      final r = SmaliPlanParser.parse(
        '{"tool_calls":[{"function":{"name":"search_classes","arguments":"{}"}}]}',
      );
      expect(r.isAnalysisComplete, isFalse);
      expect(r.modifications, isEmpty);
    });

    test('blank input not complete', () {
      expect(SmaliPlanParser.parse('').isAnalysisComplete, isFalse);
      expect(SmaliPlanParser.parse('   ').isAnalysisComplete, isFalse);
    });
  });

  group('SmaliPlanParser plan blocks', () {
    test('parses a strict SMALI_PLAN block', () {
      const text = '''
[SMALI_PLAN]
class: com.example.app.VipManager
method: isVip
```smali
.method public isVip()Z
    .locals 1
    const/4 v0, 0x1
    return v0
.end method
```
[SMALI_PLAN_END]
[ANALYSIS_COMPLETE]
''';
      final r = SmaliPlanParser.parse(text);
      expect(r.isAnalysisComplete, isTrue);
      expect(r.modifications, hasLength(1));
      final mod = r.modifications.first;
      expect(mod.className, 'com.example.app.VipManager');
      expect(mod.methodName, 'isVip');
      expect(mod.modifiedSmali, contains('const/4 v0, 0x1'));
    });

    test('plan block missing class is ignored but still complete', () {
      const text = '''
[SMALI_PLAN]
method: one
```smali
.method one()V
  return-void
.end method
```
[SMALI_PLAN_END]
[ANALYSIS_COMPLETE]
''';
      final r = SmaliPlanParser.parse(text);
      expect(r.isAnalysisComplete, isTrue);
      expect(r.modifications, isEmpty);
    });
  });

  group('SmaliPlanParser loose format', () {
    test('parses modify blocks with before/after smali', () {
      const text = '''
```modify
class: com.example.app.VipManager | method: isVip()Z | reason: r
```
修改前:
```smali
.method isVip()Z
  iget-boolean v0, p0, Lcom/example/app/VipManager;->isPremium:Z
  return v0
.end method
```
修改后:
```smali
.method isVip()Z
  const/4 v0, 0x1
  return v0
.end method
```
''';
      final r = SmaliPlanParser.parse(text);
      expect(r.isAnalysisComplete, isTrue);
      expect(r.modifications, hasLength(1));
      expect(r.modifications.first.modifiedSmali, contains('const/4 v0, 0x1'));
      expect(r.modifications.first.modifiedSmali, isNot(contains('isPremium')));
    });

    test('no plan and no marker => not complete', () {
      final r = SmaliPlanParser.parse('分析完成，登录使用 AES。');
      expect(r.isAnalysisComplete, isFalse);
      expect(r.modifications, isEmpty);
    });
  });
}
