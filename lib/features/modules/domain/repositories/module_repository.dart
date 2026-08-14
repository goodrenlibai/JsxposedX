import 'package:JsxposedX/features/modules/domain/models/bundled_module.dart';
import 'package:JsxposedX/features/modules/domain/models/module_export_result.dart';

/// Contract for everything related to bundled Magisk modules.
///
/// This abstraction keeps the UI layer decoupled from *how* modules are stored
/// and exported, so alternative storage back-ends (app-private files, raw
/// assets, SD card, ...) can be plugged in without touching the pages.
abstract interface class ModuleRepository {
  /// List all modules that ship inside the app bundle.
  Future<List<BundledModule>> getBundledModules();

  /// Whether the app-private working copy of a module has been initialized.
  Future<bool> isModuleInitialized(String moduleId);

  /// Initialize (materialize) a bundled module into app-private storage so it
  /// can be exported later without any network access. No-op if already done.
  Future<void> initializeModule(BundledModule module,
      {void Function(int done, int total, String current)? onProgress});

  /// Initialize every bundled module. Used during first launch.
  Future<void> initializeAllModules(
      {void Function(String moduleId, int done, int total)? onProgress});

  /// Build a Magisk-flashable zip for the given module and write it into
  /// [outputDirectory]. Returns the path of the written file.
  Future<ModuleExportResult> exportModule(
    BundledModule module, {
    required String outputDirectory,
    void Function(int completed, int total, String currentFile)? onProgress,
  });
}
