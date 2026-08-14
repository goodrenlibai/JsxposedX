import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A card that shows a block of copyable text (prompt or result) with a
/// one-tap "copy" button.
class ManualCopyCard extends StatelessWidget {
  const ManualCopyCard({
    super.key,
    required this.title,
    required this.body,
    required this.onCopy,
    required this.accent,
    this.selectable = true,
  });

  final String title;
  final String body;
  final VoidCallback onCopy;
  final Color accent;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.content_copy, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: selectable
                      ? SelectableText(
                          body,
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        )
                      : Text(
                          body,
                          style: const TextStyle(fontSize: 12, height: 1.5),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
