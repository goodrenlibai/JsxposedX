# 新增功能说明（内置模块 + 人工发送模式）

本文档说明本分支新增的两大能力：**内置 Magisk 模块导出** 与 **AI 逆向「人工发送」半自动模式**。

> 说明：以下为新功能的技术实现与扩展指南，原有 AI 自动逆向接口全部保持不变。

---

## 一、内置模块与配置导出页

### 背景
旧版本中，用户需要使用 Magisk（面具）Frida 模块时，需要自行去外部链接下载模块 zip，属于“向作者索取资源”。

### 改动
- 模块的全部资源已**直接内置**到应用 `assets/modules/jsxposedx-frida/` 下，包括：
  - `module.prop`（模块元数据）
  - `customize.sh` / `uninstall.sh` / `verify.sh`（安装/卸载/校验脚本）
  - `META-INF/com/google/android/update-binary` + `updater-script`
  - `config.json`（Frida 注入配置模板）
  - `lib/*.so`（Zygisk 原生注入库，4 种 ABI）
  - `gadget/*.so.xz`（Frida gadget 二进制，4 种 ABI）
- 内置资源在**应用首次启动**或打开配置页时自动初始化（复制到应用私有目录 `jsxposedx_modules/`），全程**不依赖网络下载与外部存储**。
- 新增配置页，入口在：
  - `设置 → 模块 → 内置模块配置`
  - 首页 Frida 卡片下方的“内置模块配置”按钮（替换了原来的外链下载）

### 配置页能力
- 列出所有内置模块（来源：`assets/modules/manifest.json`）。
- **多选**任意模块。
- **选择导出路径**（系统文件夹选择器）。
- 导出时显示**进度**（当前模块 / 总数 + 进度条）。
- 导出完成后显示**结果反馈**（成功路径、大小、警告、失败原因）。
- 导出的 zip 为**标准 Magisk 可刷入包**（含 `META-INF`、`customize.sh`、校验 `sha256sum`），用户直接用 Magisk 管理器刷入即可。

### 关键实现文件
- `lib/core/utils/zip_writer.dart` —— 自包含 ZIP 写入器（STORE 方式，无需第三方依赖）。
- `lib/features/modules/domain/models/bundled_module.dart` —— 模块模型。
- `lib/features/modules/domain/repositories/module_repository.dart` —— 仓库接口（便于替换存储后端）。
- `lib/features/modules/data/repositories/module_repository_impl.dart` —— 读取 manifest、初始化、导出（自动重算 sha256sum）。
- `lib/features/modules/presentation/providers/modules_provider.dart` —— Riverpod 提供者（无代码生成）。
- `lib/features/modules/presentation/pages/modules_config_page.dart` —— 配置导出页。

### 扩展新模块
1. 在 `assets/modules/<moduleId>/` 放入 Magisk 模块结构（`module.prop`、脚本、二进制等）。
2. 在 `assets/modules/manifest.json` 的 `modules` 数组中增加一条记录（`id/name/rootPath/assets/optionalAssets/exportFileName`）。
3. 应用会自动识别并支持导出，无需改其他代码。

---

## 二、AI 逆向「人工发送」半自动模式

### 背景
原有的 AI 自动逆向依赖内置/自建 AI 接口（API key / 中转站）。本功能让用户**使用任意免费外部 AI**（ChatGPT、Claude、文心一言等）完成相同的逆向分析。

### 使用流程
1. 进入项目 →「人工发送」（Manual AI），或 API 手册页右上角的「人工发送」。
2. 输入需求 → 点击「生成提示词」，软件生成一段包含系统提示词 + 工具清单 + 上下文的提示词，并提供**复制**按钮。
3. 把提示词粘贴到外部 AI，AI 返回后，将回答**粘贴回软件** → 点击「确认」。
4. 软件**自动解析** AI 返回内容，识别其中要执行的工具/模块，并**执行对应操作**，返回执行结果。
5. 再次**复制结果**发给外部 AI 继续处理，再把新回答粘贴回来。
6. 循环往复，直到任务完成。

### 交互与状态管理
- 顶部**步骤横幅**清晰展示当前处于哪一步（输入 → 复制提示词 → 粘贴回答 → 执行工具 → 复制结果）。
- **复制/粘贴**入口直接内联在对应卡片上。
- 保留**上下文**：每一轮历史（需求、AI 回复、工具调用、工具结果）都会注入到下一轮提示词中。
- 支持**中断/重置本轮、继续、重新开始**。
- 历史记录区展示所有已完成的轮次。

### 容错解析
`manual_response_parser.dart` 兼容多种外部 AI 返回格式，按顺序尝试：
1. OpenAI / Anthropic 函数调用 JSON（`tool_calls` 数组）。
2. 原始 JSON 数组 `[{name, arguments}]`。
3. 含 `tool` / `function` / `output` 的 JSON 对象。
4. Markdown ```json 代码块。
5. XML 风格 `<tool_call><name>…</name><arguments>…</arguments></tool_call>`。
6. 行式 `TOOL: name ARGS: {...}` / `[tool]name[/tool]`。
7. 全文扫描已知工具名 + JSON 参数。

未知工具名会被丢弃并给出警告，不会整体失败。

### 与原 AI 自动逆向的关系
- **完全复用同一环境**：工具定义（`ApkReverseChatToolsSpec`）与工具执行器（`ToolExecutor`），因此两个模式分析能力一致。
- **原有 AI 自动逆向接口保留不变**：`AiReversePage` 及其 `aiChatRuntimeProvider` 未做任何破坏性改动。

### 关键实现文件
- `lib/features/ai/manual/domain/services/manual_reverse_controller.dart` —— 会话控制器（状态机）。
- `lib/features/ai/manual/domain/services/manual_prompt_builder.dart` —— 提示词/结果拼装。
- `lib/features/ai/manual/domain/services/manual_response_parser.dart` —— 多格式容错解析。
- `lib/features/ai/manual/presentation/pages/manual_ai_reverse_page.dart` —— APK 逆向人工发送页。
- `lib/features/ai/manual/presentation/pages/manual_qa_page.dart` —— 通用无工具 Q&A 人工发送页（用于 API 手册）。
- `lib/features/ai/manual/presentation/widgets/manual_step_banner.dart` / `manual_copy_card.dart` —— 步骤横幅 / 复制卡片。

---

## 三、合规声明
本项目为开源技术研究工具，新功能仅用于软件调试、程序分析、内存机制学习、开发测试及授权环境研究等合法用途。使用者应自行确保其使用行为符合所在地法律法规及相关服务条款。
