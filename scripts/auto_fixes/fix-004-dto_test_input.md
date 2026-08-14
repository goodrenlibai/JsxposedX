# fix-004 — overlay_window_dto 测试输入错误

- **类型**：测试层输入错误（测试脚本缺陷）
- **文件**：`test/features/overlay_window/data/models/overlay_window_dto_test.dart`
- **发现方式**：执行既存测试时，`OverlayWindowPayloadDto` / `OverlayWindowEventDto` 相关用例失败。

## 原因
测试把 **枚举对象**（`OverlayWindowDisplayMode.panel`、`OverlayWindowEventType.bubbleTap` 等）作为原始映射的值传入 DTO 的 `fromRaw`/`maybeFromRaw`，而 DTO 的解析契约读取的是**序列化字符串**（即 `enum.name`）：

- `_displayModeFromRaw(raw)` 比较 `raw.toString() == 'panel'`；枚举对象 `toString()` 为 `OverlayWindowDisplayMode.panel`，不匹配 → 回落为 `bubble`。
- `OverlayWindowEventDto.maybeFromRaw` 期望 `'event'` 为 `name` 字符串，传入枚举对象 → 无法解析 → 返回 `null`。

这与 DTO `toRaw()` 的序列化格式（写入 `.name`）不一致，属测试数据错误，非业务缺陷。

## 修复前
- payload 测试：`fromRaw({'displayMode': OverlayWindowDisplayMode.panel})` → `displayMode == bubble`（错误）
- event 测试：`maybeFromRaw({'event': OverlayWindowEventType.bubbleTap})` → `null`（错误）

## 修复后
- 传入 `OverlayWindowDisplayMode.panel.name`（即 `'panel'`）
- 传入 `OverlayWindowEventType.bubbleTap.name`（即 `'bubbleTap'`）
- 传入 `OverlayWindowEventType.bubbleDragEnd.name`（即 `'bubbleDragEnd'`）

## 影响范围
仅修正测试输入以匹配 DTO 的既有序列化契约；不改动任何业务代码。

## 回归验证
- 重新运行 `test/features/overlay_window/data/models/overlay_window_dto_test.dart` ✅ 7/7 通过
