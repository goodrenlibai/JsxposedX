import 'package:JsxposedX/features/modules/data/repositories/module_repository_impl.dart';
import 'package:JsxposedX/features/modules/domain/models/bundled_module.dart';
import 'package:JsxposedX/features/modules/domain/repositories/module_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Plain Riverpod providers (no codegen) for the bundled-module subsystem.
///
/// Using a hand-written provider keeps this new feature buildable without
/// running `build_runner`, and makes the dependency easy to swap/test.

final moduleRepositoryProvider = Provider<ModuleRepository>(
  (ref) => const ModuleRepositoryImpl(),
);

/// Async list of bundled modules.
final bundledModulesProvider = FutureProvider<List<BundledModule>>(
  (ref) => ref.watch(moduleRepositoryProvider).getBundledModules(),
);

/// Initialize all bundled modules (called on first launch).
final initializeAllModulesProvider = FutureProvider<void>(
  (ref) => ref.watch(moduleRepositoryProvider).initializeAllModules(),
);

/// Per-module initialized status.
final moduleInitializedProvider = FutureProvider.family<bool, String>(
  (ref, moduleId) =>
      ref.watch(moduleRepositoryProvider).isModuleInitialized(moduleId),
);
