import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/services/tool_executor.dart';
import 'package:JsxposedX/features/ai/manual/domain/services/manual_reverse_controller.dart';
import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_copy_card.dart';
import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_step_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// A generic manual (semi-automatic) chat page for AI modules that expose no
/// tool calls — i.e. the copy-prompt / paste-answer loop for documentation
/// helpers (e.g. the API manual). It reuses [ManualReverseController] with an
/// empty tool set, so every external-AI answer is treated as a conclusion.
class ManualQaPage extends HookWidget {
  const ManualQaPage({
    super.key,
    required this.title,
    required this.systemPrompt,
  });

  final String title;
  final String systemPrompt;

  @override
  Widget build(BuildContext context) {
    final isZh = context.isZh;
    final controller = useMemoized(
      () => ManualReverseController(
        systemPrompt: systemPrompt,
        toolDefinitions: const [],
        toolExecutor: ToolExecutor(handlers: const []),
        isZh: isZh,
      ),
      [systemPrompt, isZh],
    );
    useListenable(controller);

    final step = useState(ManualReverseUiStep.input);
    final requestInput = useTextEditingController();
    final aiResponseInput = useTextEditingController();
    final currentPrompt = useState<String?>(null);
    final currentResult = useState<String?>(null);

    void generatePrompt() {
      final request = requestInput.text.trim();
      if (request.isEmpty) {
        ToastMessage.show(isZh ? '请输入需求' : 'Enter a request');
        return;
      }
      currentPrompt.value = controller.generatePrompt(request);
      currentResult.value = null;
      aiResponseInput.clear();
      step.value = ManualReverseUiStep.promptReady;
    }

    Future<void> confirm() async {
      final response = aiResponseInput.text.trim();
      if (response.isEmpty) {
        ToastMessage.show(isZh ? '请粘贴外部 AI 返回' : 'Paste the AI reply');
        return;
      }
      step.value = ManualReverseUiStep.executing;
      try {
        final result = await controller.execute(response);
        currentResult.value = result;
        step.value = ManualReverseUiStep.resultReady;
      } catch (e) {
        ToastMessage.show('$e');
        step.value = ManualReverseUiStep.awaitingAi;
      }
    }

    void restart() {
      controller.restart();
      currentPrompt.value = null;
      currentResult.value = null;
      requestInput.clear();
      aiResponseInput.clear();
      step.value = ManualReverseUiStep.input;
    }

    Future<void> copy(String text) async {
      await Clipboard.setData(ClipboardData(text: text));
      ToastMessage.show(isZh ? '已复制' : 'Copied');
    }

    return Scaffold(
      appBar: AppBar(title: Text('$title · ${isZh ? '人工发送' : 'Manual'}')),
      body: SafeArea(
        child: Column(
          children: [
            ManualStepBanner(step: step.value, isZh: isZh),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: requestInput,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: isZh ? '输入你的问题/需求' : 'Enter your question',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: restart,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(isZh ? '重新开始' : 'Restart'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: generatePrompt,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(isZh ? '生成提示词' : 'Generate prompt'),
                      ),
                    ],
                  ),
                  if (currentPrompt.value != null) ...[
                    const SizedBox(height: 16),
                    ManualCopyCard(
                      title: isZh ? '复制提示词发给外部 AI' : 'Copy prompt to external AI',
                      body: currentPrompt.value!,
                      onCopy: () => copy(currentPrompt.value!),
                      accent: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                  if (currentPrompt.value != null &&
                      (step.value == ManualReverseUiStep.awaitingAi ||
                          step.value == ManualReverseUiStep.promptReady)) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: aiResponseInput,
                      minLines: 4,
                      maxLines: 10,
                      decoration: InputDecoration(
                        hintText: isZh ? '粘贴外部 AI 的回答...' : 'Paste the AI reply...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed:
                              step.value == ManualReverseUiStep.executing
                                  ? null
                                  : confirm,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(isZh ? '确认' : 'Confirm'),
                        ),
                      ],
                    ),
                  ],
                  if (currentResult.value != null) ...[
                    const SizedBox(height: 16),
                    ManualCopyCard(
                      title: isZh ? '外部 AI 的回答' : 'External AI answer',
                      body: currentResult.value!,
                      onCopy: () => copy(currentResult.value!),
                      accent: Colors.teal,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
