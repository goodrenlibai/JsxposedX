import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration test that validates the bundled module manifest against the
/// on-disk asset folder, so a broken bundle (missing binary / stale hash) is
/// caught before release.
void main() {
  final projectRoot = Directory.current.path;

  test('manifest.json is present and valid JSON', () {
    final f = File('$projectRoot/assets/modules/manifest.json');
    expect(f.existsSync(), isTrue, reason: 'manifest missing');
    final decoded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['modules'], isA<List>());
  });

  test('every required module asset exists on disk', () {
    final manifest = jsonDecode(
          File('$projectRoot/assets/modules/manifest.json').readAsStringSync(),
        ) as Map<String, dynamic>;
    final modules = (manifest['modules'] as List).cast<Map<String, dynamic>>();
    expect(modules, isNotEmpty);

    for (final m in modules) {
      final root = m['rootPath'] as String;
      final required = (m['assets'] as List).cast<String>();
      for (final rel in required) {
        expect(
          File('$projectRoot/$root/$rel').existsSync(),
          isTrue,
          reason: 'required asset missing: $root/$rel',
        );
      }
    }
  });

  test('zygisk module bundles at least one ABI native library', () {
    final manifest = jsonDecode(
          File('$projectRoot/assets/modules/manifest.json').readAsStringSync(),
        ) as Map<String, dynamic>;
    final modules = (manifest['modules'] as List).cast<Map<String, dynamic>>();
    for (final m in modules) {
      if (m['category'] != 'zygisk') {
        continue;
      }
      final root = m['rootPath'] as String;
      final optional = (m['optionalAssets'] as List).cast<String>();
      final hasLib = optional.any((rel) {
        final isLib = rel.startsWith('lib/') && rel.endsWith('.so');
        return isLib && File('$projectRoot/$root/$rel').existsSync();
      });
      expect(hasLib, isTrue,
          reason: 'zygisk module ${m['id']} must include a native .so');
    }
  });

  test('bundled .sha256sum matches the actual file content', () {
    final f = File('$projectRoot/assets/modules/jsxposedx-frida/module.prop');
    expect(f.existsSync(), isTrue);
    final actual = sha256.convert(f.readAsBytesSync()).toString();
    final sumFile = File(
      '$projectRoot/assets/modules/jsxposedx-frida/module.prop.sha256sum',
    );
    expect(sumFile.existsSync(), isTrue);
    expect(sumFile.readAsStringSync().trim(), actual,
        reason: 'sha256sum is stale');
  });
}
