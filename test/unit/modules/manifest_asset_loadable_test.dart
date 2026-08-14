import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against the reported bug:
///   "Unable to load asset: assets/modules/manifest.json. The asset does not
///    exist or has empty data."
///
/// The app loads this via [rootBundle.loadString]. This test exercises the
/// exact same code path so the bundle must actually contain the asset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manifest.json is loadable via rootBundle and non-empty', () async {
    final raw = await rootBundle.loadString('assets/modules/manifest.json');
    expect(raw.trim(), isNotEmpty, reason: 'asset must not be empty');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['modules'], isA<List>());
  });

  test('bundled module files are loadable via rootBundle', () async {
    // module.prop is a required asset of the bundled frida module.
    final prop = await rootBundle.loadString(
      'assets/modules/jsxposedx-frida/module.prop',
    );
    expect(prop, contains('id=jsxposedx-frida'));
  });
}
