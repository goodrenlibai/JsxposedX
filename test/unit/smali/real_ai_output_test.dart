import 'package:JsxposedX/features/smali/domain/services/smali_plan_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the REAL AI output format the user encountered (modify blocks +
/// before/after smali blocks, NO [ANALYSIS_COMPLETE]/[SMALI_PLAN] markers).
const realAiOutput = '''
审计结论

项目 内容
包名 com.duapps.recorder
版本 2.4.8.4
VIP判断入口 xr2.f(Context) → VIP状态；xr2.a(Context) → 完整VIP有效性
核心类 mb0 (管理类)、lb0 (SP存取)、xr2 (对外接口)

Hook 方案

```javascript
// Frida Hook 脚本 - 解锁 VIP
Fx.use("com.duapps.recorder.xr2").returnConst("f", ["android.content.Context"], true);
```

完整 Smali 代码修改方案（重打包）

修改点 1：lb0.smali — VIP状态读取

```modify
class: com.duapps.recorder.lb0 | method: A()Z | file: smali/com/duapps/recorder/lb0.smali | reason: 强制返回 true
```

修改前：

```smali
.method public A()Z
    .locals 2
    const-string v0, "k_pd"
    invoke-direct {p0, v0, v1}, Lcom/duapps/recorder/lb0;->c(Ljava/lang/String;Z)Z
    move-result v0
    return v0
.end method
```

修改后：

```smali
.method public A()Z
    .locals 2
    # MODIFIED: 强制返回 true，解锁 VIP
    const/4 v0, 0x1
    return v0
.end method
```

修改点 2：lb0.smali — VIP过期时间读取

```modify
class: com.duapps.recorder.lb0 | method: x()J | file: smali/com/duapps/recorder/lb0.smali | reason: 强制返回 -1
```

修改后：

```smali
.method public x()J
    .locals 2
    # MODIFIED: 强制返回 -1（永久 VIP）
    const-wide/16 v0, -0x1
    return-wide v0
.end method
```

修改点 3：mb0.smali — 核心VIP状态判断

```modify
class: com.duapps.recorder.mb0 | method: p(Landroid/content/Context;)Z | file: smali/com/duapps/recorder/mb0.smali | reason: 强制返回 true
```

修改后：

```smali
.method public static p(Landroid/content/Context;)Z
    .locals 1
    # MODIFIED: 强制返回 true
    const/4 p0, 0x1
    return p0
.end method
```
''';

void main() {
  test('parses real AI output with modify blocks + after smali', () {
    final r = SmaliPlanParser.parse(realAiOutput);
    expect(r.isAnalysisComplete, isTrue, reason: 'plan present => complete');
    expect(r.modifications, isNotEmpty);

    final classes = r.modifications.map((m) => m.className).toList();
    final methods = r.modifications.map((m) => m.methodName).toList();
    expect(classes, containsAll([
      'com.duapps.recorder.lb0',
      'com.duapps.recorder.lb0',
      'com.duapps.recorder.mb0',
    ]));
    expect(methods, containsAll(['A', 'x', 'p']));

    // Each modification's smali should be the "after" (modified) version.
    final a = r.modifications.firstWhere((m) => m.methodName == 'A');
    expect(a.modifiedSmali, contains('const/4 v0, 0x1'));
    expect(a.modifiedSmali, isNot(contains('k_pd')));

    final x = r.modifications.firstWhere((m) => m.methodName == 'x');
    expect(x.modifiedSmali, contains('const-wide/16 v0, -0x1'));

    final p = r.modifications.firstWhere((m) => m.methodName == 'p');
    expect(p.modifiedSmali, contains('const/4 p0, 0x1'));
  });
}
