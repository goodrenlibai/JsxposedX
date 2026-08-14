import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:JsxposedX/core/utils/zip_writer.dart';
import 'package:JsxposedX/features/modules/domain/models/bundled_module.dart';
import 'package:JsxposedX/features/modules/domain/models/module_export_result.dart';
import 'package:JsxposedX/features/modules/domain/repositories/module_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Default implementation backed by the Flutter asset bundle.
///
/// Bundled modules live under `assets/modules/<id>/` (declared via the
/// `assets/` entry in pubspec.yaml). This implementation:
///  1. reads the module manifest from the asset bundle,
///  2. enumerates module files via `AssetManifest.json`,
///  3. materializes them into app-private storage on first launch,
///  4. exports a Magisk-flashable zip straight from the asset bytes.
class ModuleRepositoryImpl implements ModuleRepository {
  const ModuleRepositoryImpl();

  static const String _manifestAsset = 'assets/modules/manifest.json';
  static const String _moduleAssetPrefix = 'assets/modules/';

  @override
  Future<List<BundledModule>> getBundledModules() async {
    final raw = await rootBundle.loadString(_manifestAsset);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final items = (map['modules'] as List).cast<Map<String, dynamic>>();
    return items.map((e) {
      final int versionCode;
      final rawCode = e['versionCode'];
      versionCode = rawCode is int ? rawCode : int.tryParse('$rawCode') ?? 0;
      return BundledModule(
        id: e['id'] as String,
        name: e['name'] as String? ?? e['id'] as String,
        version: e['version'] as String? ?? '',
        versionCode: versionCode,
        author: e['author'] as String? ?? '',
        description: e['description'] as String? ?? '',
        category: e['category'] as String? ?? '',
        flavor: e['flavor'] as String? ?? '',
        rootPath: e['rootPath'] as String? ?? '$_moduleAssetPrefix${e['id']}',
        requiredAssets: (e['assets'] as List?)?.cast<String>() ?? const [],
        optionalAssets: (e['optionalAssets'] as List?)?.cast<String>() ??
            const [],
        exportFileName: e['exportFileName'] as String? ??
            '${e['id']}-${e['version']}.zip',
      );
    }).toList(growable: false);
  }

  /// List asset paths (absolute, e.g. `assets/modules/jsxposedx-frida/...`)
  /// that belong to the given module, sorted for deterministic zips.
  ///
  /// Uses [AssetManifest.loadFromAssetBundle] instead of hard-coding
  /// `AssetManifest.json`: in release builds the framework ships the manifest
  /// as the binary `AssetManifest.bin`, and reading the raw `.json` asset
  /// throws "Unable to load asset: AssetManifest.json". This API reads the
  /// correct manifest format for both debug and release automatically.
  Future<List<String>> _listModuleAssets(BundledModule module) async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final prefix = '${module.rootPath}/';
    return assetManifest
        .listAssets()
        .where((path) => path.startsWith(prefix))
        .toList(growable: false)
      ..sort();
  }

  Future<Uint8List> _readAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer
        .asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Future<bool> isModuleInitialized(String moduleId) async {
    final dir = await _moduleWorkDir(moduleId);
    return File(p.join(dir.path, '.initialized')).existsSync();
  }

  Future<Directory> _moduleWorkDir(String moduleId) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'jsxposedx_modules', moduleId));
  }

  @override
  Future<void> initializeModule(
    BundledModule module, {
    void Function(int done, int total, String current)? onProgress,
  }) async {
    if (await isModuleInitialized(module.id)) {
      return;
    }
    final files = await _listModuleAssets(module);
    final dir = await _moduleWorkDir(module.id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    var done = 0;
    for (final assetPath in files) {
      final relative = assetPath.substring('${module.rootPath}/'.length);
      final target = File(p.join(dir.path, relative));
      await target.parent.create(recursive: true);
      final bytes = await _readAssetBytes(assetPath);
      await target.writeAsBytes(bytes, flush: true);
      done += 1;
      onProgress?.call(done, files.length, relative);
    }
    // Marker file indicating initialization completed.
    await File(p.join(dir.path, '.initialized'))
        .writeAsString('${DateTime.now().toIso8601String()}\n', flush: true);
  }

  @override
  Future<void> initializeAllModules(
      {void Function(String moduleId, int done, int total)? onProgress}) async {
    final modules = await getBundledModules();
    for (final module in modules) {
      await initializeModule(
        module,
        onProgress: (done, total, _) =>
            onProgress?.call(module.id, done, total),
      );
    }
  }

  /// Build the list of files to bundle into the Magisk zip:
  /// every asset under the module folder, plus a freshly computed `.sha256sum`
  /// sibling for each (required by the module's verify.sh).
  Future<List<ZipEntryData>> _buildZipEntries(BundledModule module) async {
    final files = await _listModuleAssets(module);
    // Skip the initialization marker if it somehow leaked into the bundle.
    final targets = files
        .where((p) => !p.endsWith('.initialized'))
        .toList(growable: false);

    final entries = <ZipEntryData>[];
    final missingRequired = <String>[];

    for (final assetPath in targets) {
      final relative = assetPath.substring('${module.rootPath}/'.length);
      // Don't copy pre-existing .sha256sum from the bundle; we recompute them.
      if (relative.endsWith('.sha256sum')) {
        continue;
      }
      final bytes = await _readAssetBytes(assetPath);
      entries.add(ZipEntryData(path: relative, bytes: bytes));
    }

    // Verify required assets are all present.
    final present = entries.map((e) => e.path).toSet();
    for (final required in module.requiredAssets) {
      if (!present.contains(required)) {
        missingRequired.add(required);
      }
    }

    if (missingRequired.isNotEmpty) {
      throw StateError('模块 ${module.id} 缺少必需文件: ${missingRequired.join(', ')}');
    }

    // Compute sha256sum for every bundled file (except .sha256sum itself).
    final finalEntries = <ZipEntryData>[];
    for (final entry in entries) {
      final hash = sha256.convert(entry.bytes).toString();
      finalEntries.add(entry);
      finalEntries.add(
        ZipEntryData(
          path: '${entry.path}.sha256sum',
          bytes: Uint8List.fromList(utf8.encode('$hash\n')),
        ),
      );
    }
    return finalEntries;
  }

  @override
  Future<ModuleExportResult> exportModule(
    BundledModule module, {
    required String outputDirectory,
    void Function(int completed, int total, String currentFile)? onProgress,
  }) async {
    final warnings = <String>[];
    try {
      final entries = await _buildZipEntries(module);
      if (entries.isEmpty) {
        return ModuleExportResult.fail(
          moduleId: module.id,
          error: '模块 ${module.id} 没有任何可导出的文件',
        );
      }

      // Warn about missing optional binaries that make the module unusable on
      // some / all devices.
      final present = entries.map((e) => e.path).toSet();
      for (final optional in module.optionalAssets) {
        if (!present.contains(optional)) {
          warnings.add('缺少可选二进制: $optional');
        }
      }
      // For a zygisk module at least one ABI must be present.
      if (module.isZygisk) {
        final hasLib = module.optionalAssets.any(
          (optional) =>
              optional.startsWith('lib/') &&
              optional.endsWith('.so') &&
              present.contains(optional),
        );
        if (!hasLib) {
          warnings.add('未包含任何 Zygisk 原生库（lib/*.so），模块可能无法在设备上生效');
        }
      }

      final outDir = Directory(outputDirectory);
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      final safeName = p.basename(module.exportFileName);
      final outFile = File(p.join(outDir.path, safeName));

      var done = 0;
      final total = entries.length;
      onProgress?.call(done, total, '开始打包...');
      final bytes = ZipWriter.write(entries: entries);
      await outFile.writeAsBytes(bytes, flush: true);
      done = total;
      onProgress?.call(done, total, safeName);

      return ModuleExportResult.ok(
        moduleId: module.id,
        outputPath: outFile.path,
        bytesWritten: bytes.lengthInBytes,
        warnings: warnings,
      );
    } catch (error) {
      return ModuleExportResult.fail(
        moduleId: module.id,
        error: '$error',
        warnings: warnings,
      );
    }
  }
}
