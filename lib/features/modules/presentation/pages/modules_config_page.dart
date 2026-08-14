import 'package:JsxposedX/common/pages/toast.dart';
import 'package:JsxposedX/core/extensions/context_extensions.dart';
import 'package:JsxposedX/features/modules/domain/models/bundled_module.dart';
import 'package:JsxposedX/features/modules/domain/models/module_export_result.dart';
import 'package:JsxposedX/features/modules/presentation/providers/modules_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Configuration page for bundled Magisk modules.
///
/// Users can browse the modules shipped inside the app, initialize them into
/// app-private storage, multi-select any subset, pick an export folder and
/// generate a Magisk-flashable zip for each. Everything is fully offline.
class ModulesConfigPage extends HookConsumerWidget {
  const ModulesConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isZh = context.isZh;
    final modulesAsync = ref.watch(bundledModulesProvider);
    final selected = useState<Map<String, bool>>({});

    // Auto-initialize all bundled modules once on first launch.
    useEffect(() {
      Future.microtask(() {
        ref.read(initializeAllModulesProvider);
      });
      return null;
    }, []);

    final exporting = useState(false);
    final exportProgress = useState<(int, int)?>(null);

    Future<void> onExport() async {
      final modules = modulesAsync.value ?? [];
      final chosen =
          modules.where((m) => selected.value[m.id] ?? false).toList();
      if (chosen.isEmpty) {
        ToastMessage.show(
          isZh ? '请先选择至少一个模块' : 'Please select at least one module',
        );
        return;
      }

      // Pick export folder.
      String? dir;
      try {
        dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: isZh ? '选择导出文件夹' : 'Select export folder',
        );
      } catch (_) {
        dir = null;
      }
      if (dir == null || dir.isEmpty) {
        return;
      }

      exporting.value = true;
      exportProgress.value = (0, chosen.length);
      final results = <ModuleExportResult>[];
      try {
        for (var i = 0; i < chosen.length; i++) {
          exportProgress.value = (i, chosen.length);
          final module = chosen[i];
          final result = await ref
              .read(moduleRepositoryProvider)
              .exportModule(
                module,
                outputDirectory: dir,
                onProgress: (done, total, file) {
                  exportProgress.value = (i, chosen.length);
                },
              );
          results.add(result);
        }
        _showResults(context, results);
      } finally {
        exporting.value = false;
        exportProgress.value = null;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isZh ? '内置模块配置' : 'Bundled Modules'),
        actions: [
          TextButton.icon(
            onPressed: exporting.value ? null : onExport,
            icon: exporting.value
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_rounded),
            label: Text(isZh ? '导出' : 'Export'),
          ),
        ],
      ),
      body: modulesAsync.when(
        data: (modules) {
          return Column(
            children: [
              if (exporting.value && exportProgress.value != null)
                _ExportProgressBanner(
                  progress: exportProgress.value!,
                  isZh: isZh,
                ),
              Expanded(
                child: modules.isEmpty
                    ? Center(
                        child: Text(
                          isZh ? '暂无内置模块' : 'No bundled modules',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: modules.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final module = modules[index];
                          return _ModuleTile(
                            module: module,
                            checked: selected.value[module.id] ?? false,
                            onChanged: (value) {
                              selected.value = {
                                ...selected.value,
                                module.id: value,
                              };
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${(isZh ? '加载失败' : 'Load failed')}: $e')),
      ),
    );
  }

  void _showResults(BuildContext context, List<ModuleExportResult> results) {
    final isZh = context.isZh;
    SmartDialog.showToast(isZh ? '导出完成' : 'Export finished');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isZh ? '导出结果' : 'Export results'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: results
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: r.success
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle,
                                      color: Colors.green, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${r.moduleId} ✓',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Text(
                                  '${r.outputPath}\n'
                                  '${_formatSize(r.bytesWritten ?? 0)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              if (r.warnings.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(left: 24, top: 4),
                                  child: Text(
                                    r.warnings.map((w) => '⚠ $w').join('\n'),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.orange),
                                  ),
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              const Icon(Icons.cancel,
                                  color: Colors.red, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${r.moduleId} ✗  ${r.error ?? ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isZh ? '确定' : 'OK'),
          ),
        ],
      ),
    );
  }
}

/// Format a byte count into a human-readable size string.
String _formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class _ExportProgressBanner extends StatelessWidget {
  const _ExportProgressBanner({
    required this.progress,
    required this.isZh,
  });

  final (int, int) progress;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final (current, total) = progress;
    final value = total == 0 ? 0.0 : (current / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: value),
          const SizedBox(height: 6),
          Text(
            isZh
                ? '正在导出 ${current + 1}/$total 个模块...'
                : 'Exporting module ${current + 1}/$total...',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.checked,
    required this.onChanged,
  });

  final BundledModule module;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: checked,
      onChanged: (value) => onChanged(value ?? false),
      secondary: Icon(
        module.isZygisk ? Icons.bolt_rounded : Icons.settings_rounded,
        color: module.isZygisk ? Colors.deepPurpleAccent : Colors.teal,
      ),
      title: Text(
        module.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${module.id} · ${module.version}\n${module.description}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
    );
  }
}
