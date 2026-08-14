# 待人工处理问题清单（详细）

> 以下问题均为**既存测试/既有代码**中的问题，无法在当前无设备、无 root、无原生环境下安全地自动修复，需人工评估。它们不在本次「新编写测试套件」的纳入范围内；本次新编写的 121 条用例已 100% 通过。

| # | 位置 | 分类 | 原因 | 影响范围 | 建议处理方式 |
|---|------|------|------|----------|--------------|
| P1 | `test/feature/ai/presentation/providers/chat/ai_chat_action_provider_reasoning_replay_test.dart` | 空占位文件 | 文件为 **0 字节空文件**（无 `main`），导致整套测试加载阶段报 `Undefined name 'main'`。引用的是「AI chat provider reasoning replay」功能，但从未编写用例。 | 该文件自身无法加载；其余用例不受影响。 | 由作者补全该功能的测试，或删除该空占位文件。 |
| P2 | `test/features/memory_tool_overlay/presentation/providers/memory_ai_overlay_selection_provider_test.dart`（4 条用例） | 环境依赖（native/root） | 该组用例依赖内存工具的原生数据提供者（`currentSearchResultsProvider`、`currentSearchResultLivePreviewsProvider` 等，经由 `memory_tool.g.dart` pigeon 桥接原生守护进程）。在无头测试环境中这些原生数据源返回空/错误，导致 `memoryAiOverlayHasSelectedValueProvider` 恒为 `false`，与断言不符。测试仅覆盖了部分数据提供者，未覆盖原生相关提供者。 | 仅影响该文件 4 条用例；内存工具功能本身为原生+root 特性。 | 需在真机/模拟器 + root 环境下进行集成测试，或补充对原生数据提供者的桩（需理解 `memory_tool.g.dart` 桥接契约），由熟悉内存工具的实现者处理。 |

## 处理边界说明

- 未以「跳过用例 / 降低断言标准 / 删除用例 / 扩大超时 / mock 关键依赖 / 篡改测试数据」等方式掩盖上述失败。
- P1 为空文件，删除其中 0 条用例不构成「掩盖失败」，但为尊重既有文件由作者决策，仍标记为待人工处理。
- P2 为原生/root 依赖，属于自修复边界中「环境依赖」类别，禁止自动修复。

## 关闭条件

- P1：作者补全或移除该空占位文件。
- P2：在具备内存工具运行环境（root + 原生守护进程）的设备上补充集成测试，或由实现者为原生数据提供者补充可无头运行的桩并完成回归。
