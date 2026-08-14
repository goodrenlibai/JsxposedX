# fix-001 — manual_prompt_builder 插值撕裂缺陷

- **类型**：业务代码缺陷
- **文件**：`lib/features/ai/manual/domain/services/manual_prompt_builder.dart`
- **发现方式**：新增单元测试 `manual_prompt_builder_test.dart` 中 `buildToolGuide` 断言失败。

## 原因
原代码：`'- \`$_wrapName(def.name)\`: ...'`。
Dart 将 `$_wrapName` 解析为方法 `_wrapName` 的**撕裂（tear-off）**，随后紧跟的字面量 `(def.name)` 被当作普通文本拼接。因此生成的工具指南中工具名被渲染成函数对象字符串（如 `Closure: ... _wrapName ...`），而非工具名本身。

## 修复前
`buildToolGuide` 输出：`- \`Closure: (String) => String from Function '_wrapName@...':.(def.name)\`: d`

## 修复后
`buildToolGuide` 输出：`- \`get_manifest\`: 获取 Manifest`

将 `$_wrapName(def.name)` 改为 `${_wrapName(def.name)}`（用花括号限定完整表达式）。

## 影响范围
仅影响「人工发送」模式生成的提示词中工具清单的可读性；不影响功能逻辑、不影响内置 AI 自动逆向接口。

## 回归验证
- 重新运行 `test/unit/manual/manual_prompt_builder_test.dart` ✅ 全部通过
- 重新运行整套 `test/unit` + `test/widget` ✅ 通过
