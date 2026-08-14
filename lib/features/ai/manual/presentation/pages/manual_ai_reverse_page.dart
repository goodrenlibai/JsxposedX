import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_chat_tool_catalog.dart';
import 'package:JsxposedX/features/ai/manual/domain/services/manual_reverse_controller.dart';
import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_step_banner.dart';
import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_copy_card.dart';
import 'package:JsxposedX/features/ai/presentation/providers/environments/apk_reverse_chat_environment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _UiStep { initializing, input, promptReady, awaitingAi, executing, resultReady }

/// Manual (semi-automatic) send mode for APK reverse.
///
/// The user drives the loop by copying prompts to any external AI, pasting the
/// answer back, and letting the app parse + execute the tool calls. It reuses
/// the exact same environment (tools + executor) as the built-in AI auto
/// reverse, so the two modes stay consistent.
class ManualAiReversePage extends HookConsumerWidget {
  const ManualAiReversePage({super.key, required this.packageName});

  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isZh = context.isZh;
    final environment = ref.watch(
      apkReverseChatEnvironmentProvider(
        ApkReverseChatEnvironmentArgs(packageName: packageName, isZh: isZh),
      ),
    );

    final step = useState<_UiStep>(_UiStep.initializing);
    final initError = useState<String?>(null);
    final controller = useRef<ManualReverseController?>(null);

    // Initialize environment + build the manual controller once.
    useEffect(() {
      Future.microtask(() async {
        if (controller.value != null) {
          step.value = _UiStep.input;
          return;
        }
        try {
          SmartDialog.showLoading();
          final snapshot = await environment.initialize();
          final toolCatalog = snapshot.toolsSpec as AiChatToolCatalog?;
          if (toolCatalog == null || snapshot.toolExecutor == null) {
            step.value = _UiStep.input;
            return;
          }
          controller.value = ManualReverseController(
            systemPrompt: snapshot.systemPrompt,
            toolDefinitions: toolCatalog.definitions,
            toolExecutor: snapshot.toolExecutor!,
            isZh: isZh,
          );
          step.value = _UiStep.input;
        } catch (error) {
          initError.value = '$error';
          step.value = _UiStep.initializing;
        } finally {
          SmartDialog.dismiss();
        }
      });
      return () {
        // Environment adapter is disposed by its own provider.
      };
    }, [environment]);

    // Editable state.
    final requestInput = useTextEditingController();
    final aiResponseInput = useTextEditingController();
    final currentPrompt = useState<String?>(null);
    final currentResult = useState<String?>(null);
    final roundCount = useState(0);

    void generatePrompt() {
      final ctrl = controller.value;
      final request = requestInput.text.trim();
      if (ctrl == null || request.isEmpty) {
        ToastMessage.show(isZh ? '请输入需求' : 'Please enter a request');
        return;
      }
      final prompt = ctrl.generatePrompt(request);
      currentPrompt.value = prompt;
      currentResult.value = null;
      aiResponseInput.clear();
      step.value = _UiStep.promptReady;

    }

    Future<void> confirmAiResponse() async {
      final ctrl = controller.value;
      final response = aiResponseInput.text.trim();
      if (ctrl == null || response.isEmpty) {
        ToastMessage.show(
          isZh ? '请粘贴外部 AI 返回的内容' : 'Please paste the AI reply',
        );
        return;
      }
      step.value = _UiStep.executing;

      try {
        final result = await ctrl.execute(response);
        currentResult.value = result;
        roundCount.value = ctrl.rounds.length + (ctrl.copyableResult != null ? 1 : 0);
        // If the result still requests more tools, stay in "awaiting AI";
        // otherwise we keep the result ready to copy.
        step.value = ctrl.copyableResult != null
            ? _UiStep.resultReady
            : _UiStep.input;
      } catch (error) {
        ToastMessage.show('${isZh ? '执行失败' : 'Failed'}: $error');
        step.value = _UiStep.awaitingAi;
      }

    }

    void resetRound() {
      // Clear the in-progress round but keep session context & history.
      final ctrl = controller.value;
      if (ctrl == null) {
        return;
      }
      ctrl.resetRound();
      currentPrompt.value = null;
      currentResult.value = null;
      aiResponseInput.clear();
      step.value = _UiStep.input;
    }

    void continueRound() {
      // Start a fresh sub-round with the same context.
      resetRound();
    }

    void restart() {
      final ctrl = controller.value;
      if (ctrl == null) {
        return;
      }
      ctrl.restart();
      currentPrompt.value = null;
      currentResult.value = null;
      requestInput.clear();
      aiResponseInput.clear();
      roundCount.value = 0;
      step.value = _UiStep.input;

    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isZh ? '人工发送 · 逆向' : 'Manual Send · Reverse'),
      ),
      body: SafeArea(
        child: step.value == _UiStep.initializing
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  ManualStepBanner(step: _mapStep(step.value), isZh: isZh),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (initError.value != null)
                          _ErrorCard(message: initError.value!),
                        _buildRequestBody(
                          context,
                          requestInput: requestInput,
                          showReset: controller.value?.hasSession ?? false,
                          onReset: resetRound,
                          onGenerate: generatePrompt,
                        ),
                        const SizedBox(height: 16),
                        if (currentPrompt.value != null)
                          ManualCopyCard(
                            title: isZh ? '第 ${roundCount.value + 1} 步 · 请复制这段提示词发给外部 AI' : 'Step ${roundCount.value + 1} · copy this prompt to the external AI',
                            body: currentPrompt.value!,
                            onCopy: () => _copy(context, currentPrompt.value!),
                            accent: Theme.of(context).colorScheme.primary,
                          ),
                        if (currentPrompt.value != null)
                          const SizedBox(height: 16),
                        if (step.value == _UiStep.promptReady ||
                            step.value == _UiStep.awaitingAi ||
                            step.value == _UiStep.resultReady)
                          _buildAiResponseBox(
                            context,
                            aiResponseInput: aiResponseInput,
                            isExecuting: step.value == _UiStep.executing,
                            onConfirm: confirmAiResponse,
                          ),
                        if (currentResult.value != null)
                          ManualCopyCard(
                            title: isZh ? '外部 AI 结果 · 工具已执行' : 'External AI result · tools executed',
                            body: currentResult.value!,
                            onCopy: () => _copy(context, currentResult.value!),
                            accent: Colors.teal,
                          ),
                        if (_hasHistory(controller.value))
                          const SizedBox(height: 16),
                        if (_hasHistory(controller.value))
                          _buildHistory(
                            context,
                            controller.value!,
                            onContinue: continueRound,
                            onRestart: restart,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRequestBody(
    BuildContext context, {
    required TextEditingController requestInput,
    required bool showReset,
    required VoidCallback onReset,
    required VoidCallback onGenerate,
  }) {
    final isZh = context.isZh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isZh ? '1. 输入需求' : '1. Enter your request',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: requestInput,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: isZh
                ? '例如：帮我分析这个 App 的登录加密逻辑'
                : 'e.g. Analyze this app\'s login encryption logic',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showReset)
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.replay, size: 18),
                label: Text(isZh ? '重置本轮' : 'Reset round'),
              ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(isZh ? '生成提示词' : 'Generate prompt'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAiResponseBox(
    BuildContext context, {
    required TextEditingController aiResponseInput,
    required bool isExecuting,
    required VoidCallback onConfirm,
  }) {
    final isZh = context.isZh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isZh
              ? '2. 将外部 AI 的回答粘贴到这里，点击确认'
              : '2. Paste the external AI reply and confirm',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: aiResponseInput,
          minLines: 4,
          maxLines: 12,
          decoration: InputDecoration(
            hintText: isZh ? '粘贴 AI 返回内容...' : 'Paste the AI reply...',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: isExecuting ? null : onConfirm,
              icon: isExecuting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(isZh ? '确认' : 'Confirm'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHistory(
    BuildContext context,
    ManualReverseController ctrl, {
    required VoidCallback onContinue,
    required VoidCallback onRestart,
  }) {
    final isZh = context.isZh;
    final rounds = ctrl.rounds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isZh ? '历史记录' : 'History',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < rounds.length; i++)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 12,
                child: Text('${i + 1}',
                    style: const TextStyle(fontSize: 11)),
              ),
              title: Text(
                rounds[i].userRequest,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${rounds[i].toolCalls.length} tool calls',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(isZh ? '继续' : 'Continue'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(isZh ? '重新开始' : 'Restart'),
            ),
          ],
        ),
      ],
    );
  }

  bool _hasHistory(ManualReverseController? ctrl) =>
      ctrl != null && ctrl.rounds.isNotEmpty;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    ToastMessage.show(context.isZh ? '已复制' : 'Copied');
  }

  ManualReverseUiStep _mapStep(_UiStep step) {
    return switch (step) {
      _UiStep.initializing => ManualReverseUiStep.initializing,
      _UiStep.input => ManualReverseUiStep.input,
      _UiStep.promptReady => ManualReverseUiStep.promptReady,
      _UiStep.awaitingAi => ManualReverseUiStep.awaitingAi,
      _UiStep.executing => ManualReverseUiStep.executing,
      _UiStep.resultReady => ManualReverseUiStep.resultReady,
    };
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message,
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
      ),
    );
  }
}
