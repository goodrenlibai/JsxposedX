import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/ai/domain/services/ai_chat_tool_catalog.dart';
import 'package:JsxposedX/features/ai/manual/domain/services/manual_reverse_controller.dart';
import 'package:JsxposedX/features/ai/manual/presentation/widgets/manual_step_banner.dart';
import 'package:JsxposedX/features/ai/presentation/providers/environments/apk_reverse_chat_environment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _UiStep { initializing, input, promptReady, awaitingAi, executing, resultReady }

/// Manual (semi-automatic) send mode for APK reverse.
///
/// UI design goals (per user feedback on the previous layout):
///   - NO need to scroll up/down to find the action; every step drives a
///     single pinned bottom action bar.
///   - There is ALWAYS exactly ONE copy button visible, bound to the *current*
///     step, so it can never accidentally copy an earlier/initial response.
///   - Copy is disabled while a tool phase is executing, preventing the user
///     from copying a stale response before the run finishes.
///   - Each step auto-scrolls to its relevant input, and the current step is
///     clearly shown in the banner.
///
/// It reuses the exact same environment (tools + executor) as the built-in AI
/// auto reverse, so the two modes stay consistent.
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
    final scrollController = useScrollController();

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
      return null;
    }, [environment]);

    // Editable state.
    final requestInput = useTextEditingController();
    final aiResponseInput = useTextEditingController();
    final currentPrompt = useState<String?>(null);
    final currentResult = useState<String?>(null);
    final roundCount = useState(0);

    // Auto-scroll to the top of the active panel whenever the step changes so
    // the current action is always in view (no manual scrolling up/down).
    useEffect(() {
      if (step.value == _UiStep.initializing) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
      return null;
    }, [step.value]);

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
        roundCount.value =
            ctrl.rounds.length + (ctrl.copyableResult != null ? 1 : 0);
        // Copy is only enabled again once the run is fully finished.
        step.value = ctrl.copyableResult != null
            ? _UiStep.resultReady
            : _UiStep.promptReady;
      } catch (error) {
        ToastMessage.show('${isZh ? '执行失败' : 'Failed'}: $error');
        step.value = _UiStep.awaitingAi;
      }
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

    // The single, always-correct copy target for the CURRENT step.
    String? copyTarget() {
      switch (step.value) {
        case _UiStep.promptReady:
        case _UiStep.awaitingAi:
          return currentPrompt.value;
        case _UiStep.resultReady:
          return currentResult.value;
        default:
          return null;
      }
    }

    Future<void> copyCurrent() async {
      final target = copyTarget();
      if (target == null || target.isEmpty) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: target));
      ToastMessage.show(isZh ? '已复制' : 'Copied');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isZh ? '人工发送 · 逆向' : 'Manual Send · Reverse'),
        actions: [
          IconButton(
            tooltip: isZh ? '重新开始' : 'Restart',
            onPressed:
                step.value == _UiStep.executing ? null : () => restart(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: step.value == _UiStep.initializing
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  ManualStepBanner(
                    step: _mapStep(step.value),
                    isZh: isZh,
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (initError.value != null)
                          _ErrorCard(message: initError.value!),
                        // Primary panel: always shows the CURRENT step's
                        // content (input, prompt, AI-reply paste box, result).
                        _buildActivePanel(
                          context,
                          isZh: isZh,
                          step: step.value,
                          requestInput: requestInput,
                          aiResponseInput: aiResponseInput,
                          currentPrompt: currentPrompt.value,
                          currentResult: currentResult.value,
                          onConfirm: confirmAiResponse,
                        ),
                      ],
                    ),
                  ),
                  // Pinned bottom action bar — exactly one correct action.
                  _buildBottomBar(
                    context,
                    isZh: isZh,
                    step: step.value,
                    currentPrompt: currentPrompt.value,
                    currentResult: currentResult.value,
                    onGenerate: generatePrompt,
                    onCopy: copyCurrent,
                  ),
                ],
              ),
      ),
    );
  }

  /// Renders only the widgets relevant to the current step.
  Widget _buildActivePanel(
    BuildContext context, {
    required bool isZh,
    required _UiStep step,
    required TextEditingController requestInput,
    required TextEditingController aiResponseInput,
    required String? currentPrompt,
    required String? currentResult,
    required VoidCallback onConfirm,
  }) {
    switch (step) {
      case _UiStep.input:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isZh ? '输入需求' : 'Enter your request',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: requestInput,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: isZh
                    ? '例如：帮我分析这个 App 的登录加密逻辑'
                    : 'e.g. Analyze this app\'s login encryption logic',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        );

      case _UiStep.promptReady:
      case _UiStep.awaitingAi:
        // Prompt + paste box. The copy action is on the pinned bottom bar.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              isZh
                  ? '已生成提示词（点击底部按钮复制）'
                  : 'Prompt generated (copy via bottom button)',
            ),
            const SizedBox(height: 8),
            _ReadonlyBox(
              text: currentPrompt ?? '',
              maxHeight: 180,
              selectable: true,
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              isZh
                  ? '将外部 AI 的回答粘贴到这里'
                  : 'Paste the external AI reply here',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: aiResponseInput,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: isZh ? '粘贴 AI 返回内容...' : 'Paste the AI reply...',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                // Enabled at both promptReady and awaitingAi: after generating
                // the prompt the user pastes the AI reply and confirms directly.
                // (Empty input is guarded inside onConfirm with a toast.)
                onPressed: onConfirm,
                icon: const Icon(Icons.check, size: 18),
                label: Text(isZh ? '确认并执行' : 'Confirm & run'),
              ),
            ),
          ],
        );

      case _UiStep.executing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在执行工具调用...'),
            ],
          ),
        );

      case _UiStep.resultReady:
        // Tool results + paste box for the next iteration.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              isZh
                  ? '工具已执行完成（点击底部按钮复制结果发回 AI）'
                  : 'Tools executed (copy results via bottom button)',
            ),
            const SizedBox(height: 8),
            _ReadonlyBox(
              text: currentResult ?? '',
              maxHeight: 200,
              selectable: true,
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              isZh
                  ? '若需继续：粘贴外部 AI 的下一次回答'
                  : 'To continue: paste the external AI\'s next reply',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: aiResponseInput,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: isZh ? '粘贴 AI 返回内容...' : 'Paste the AI reply...',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(isZh ? '继续分析' : 'Continue'),
              ),
            ),
          ],
        );

      case _UiStep.initializing:
        return const SizedBox.shrink();
    }
  }

  /// Pinned bottom action bar. At any moment it shows exactly ONE primary
  /// action that is correct for the current step, so the user can never copy
  /// the wrong (e.g. an earlier) response by mistake.
  Widget _buildBottomBar(
    BuildContext context, {
    required bool isZh,
    required _UiStep step,
    required String? currentPrompt,
    required String? currentResult,
    required VoidCallback onGenerate,
    required VoidCallback onCopy,
  }) {
    final (label, icon, enabled, onTap) = switch (step) {
      _UiStep.input => (
        isZh ? '生成提示词' : 'Generate prompt',
        Icons.auto_awesome,
        true,
        onGenerate,
      ),
      _UiStep.promptReady => (
        isZh ? '复制提示词' : 'Copy prompt',
        Icons.copy,
        (currentPrompt?.isNotEmpty ?? false),
        onCopy,
      ),
      _UiStep.awaitingAi => (
        isZh ? '复制提示词' : 'Copy prompt',
        Icons.copy,
        (currentPrompt?.isNotEmpty ?? false),
        onCopy,
      ),
      _UiStep.executing => (
        isZh ? '正在执行，请稍候...' : 'Running...',
        Icons.hourglass_top,
        false,
        null,
      ),
      _UiStep.resultReady => (
        isZh ? '复制结果发回 AI' : 'Copy result',
        Icons.copy,
        (currentResult?.isNotEmpty ?? false),
        onCopy,
      ),
      _UiStep.initializing => (
        '',
        Icons.hourglass_top,
        false,
        null,
      ),
    };

    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton.icon(
          onPressed: enabled ? onTap : null,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
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

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    );
  }
}

class _ReadonlyBox extends StatelessWidget {
  final String text;
  final double maxHeight;
  final bool selectable;
  const _ReadonlyBox({
    required this.text,
    required this.maxHeight,
    this.selectable = true,
  });
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: selectable
              ? SelectableText(
                  text.isEmpty ? '(空)' : text,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                )
              : Text(
                  text.isEmpty ? '(空)' : text,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
        ),
      ),
    );
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
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
