import 'package:flutter/material.dart';

enum ManualReverseUiStep {
  initializing,
  input,
  promptReady,
  awaitingAi,
  executing,
  resultReady,
}

/// A compact progress banner that always shows which step of the manual loop
/// the user is currently on.
class ManualStepBanner extends StatelessWidget {
  const ManualStepBanner({super.key, required this.step, required this.isZh});

  final ManualReverseUiStep step;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _describe(context, step, isZh);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  (String, IconData, Color) _describe(
    BuildContext context,
    ManualReverseUiStep step,
    bool isZh,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    final teal = Colors.teal;
    final orange = Colors.orange;
    final red = Theme.of(context).colorScheme.error;
    return switch (step) {
      ManualReverseUiStep.initializing => (
        isZh ? '正在初始化逆向会话...' : 'Initializing reverse session...',
        Icons.hourglass_top,
        primary,
      ),
      ManualReverseUiStep.input => (
        isZh ? '步骤 1：输入需求并生成提示词' : 'Step 1: enter a request & generate a prompt',
        Icons.edit_note,
        primary,
      ),
      ManualReverseUiStep.promptReady => (
        isZh ? '步骤 2：复制提示词 → 发给外部 AI' : 'Step 2: copy the prompt to the external AI',
        Icons.copy,
        primary,
      ),
      ManualReverseUiStep.awaitingAi => (
        isZh ? '步骤 3：粘贴外部 AI 的回答' : 'Step 3: paste the external AI reply',
        Icons.paste,
        orange,
      ),
      ManualReverseUiStep.executing => (
        isZh ? '正在执行工具调用...' : 'Executing tool calls...',
        Icons.sync,
        teal,
      ),
      ManualReverseUiStep.resultReady => (
        isZh ? '步骤 4：复制结果发回 AI 继续（或已完成）' : 'Step 4: copy results back to the AI (or done)',
        Icons.check_circle,
        teal,
      ),
    };
  }
}
