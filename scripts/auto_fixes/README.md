# 自动修复记录（Auto-fix records）

本目录记录本轮测试与修复过程中所有自动修复项。每条记录包含：
位置、原因、修复前行为、修复后行为、影响范围、回归验证结果。

## 规则（自修复边界）

| 类别 | 是否允许自动修复 | 判定标准 |
|------|------------------|----------|
| 测试脚本错误 / 断言错误 / 输入错误 | ✅ 允许 | 可明确定位，属测试层问题 |
| 选择器失效 / 等待超时 / 测试数据失效 | ✅ 允许 | 属测试层问题 |
| 业务代码缺陷 | ⚠️ 仅在满足条件时允许 | 修复范围明确、影响面可控、已有对应回归用例 |
| 环境依赖（需原生/root/设备/网络） | ❌ 不允许 | 标记「待人工处理」 |

任何自动修复必须：附带修复说明、重新运行相关用例及关联回归用例、确认无新问题。

## 修复记录索引

| 记录 | 类型 | 文件 | 状态 |
|------|------|------|------|
| [fix-001](fix-001-manual_prompt_builder.md) | 业务代码缺陷 | `lib/features/ai/manual/domain/services/manual_prompt_builder.dart` | ✅ 已验证 |
| [fix-002](fix-002-zip_writer_utf8.md) | 业务代码缺陷 | `lib/core/utils/zip_writer.dart` | ✅ 已验证 |
| [fix-003](fix-003-encrypt_empty.md) | 业务代码缺陷 | `lib/core/utils/encrypt_util.dart` | ✅ 已验证 |
| [fix-004](fix-004-dto_test_input.md) | 测试层输入错误 | `test/features/overlay_window/data/models/overlay_window_dto_test.dart` | ✅ 已验证 |
