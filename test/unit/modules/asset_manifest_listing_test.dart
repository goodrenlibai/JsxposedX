import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the reported bug:
///   "Unable to load asset: \"AssetManifest.json\"."
///
/// The old code did `rootBundle.loadString('AssetManifest.json')`, which is a
/// non-bundled pseudo-asset in release builds. The fix uses
/// [AssetManifest.loadFromAssetBundle], which reads the real manifest
/// (`AssetManifest.bin` in release) for both debug and release.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset manifest lists the bundled module assets', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().toList();

    // The bundled frida module files must be present in the asset manifest.
    expect(
      assets,
      contains('assets/modules/jsxposedx-frida/module.prop'),
      reason: 'bundled module asset should be registered in the manifest',
    );
    expect(
      assets,
      contains('assets/modules/manifest.json'),
      reason: 'module manifest must be bundled',
    );
  });
}
