import 'package:JsxposedX/features/modules/domain/models/bundled_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fridaModule = BundledModule(
    id: 'jsxposedx-frida',
    name: 'JsxposedxFrida',
    version: 'v2.0.1',
    versionCode: 201,
    author: '挽风',
    description: 'desc',
    category: 'zygisk',
    flavor: 'zygisk',
    rootPath: 'assets/modules/jsxposedx-frida',
    requiredAssets: ['module.prop', 'customize.sh'],
    optionalAssets: ['lib/arm64-v8a.so', 'gadget/libgadget-arm64.so.xz'],
    exportFileName: 'JsxposedxFrida.zip',
  );

  test('carries metadata fields', () {
    expect(fridaModule.id, 'jsxposedx-frida');
    expect(fridaModule.name, 'JsxposedxFrida');
    expect(fridaModule.version, 'v2.0.1');
    expect(fridaModule.versionCode, 201);
    expect(fridaModule.author, '挽风');
    expect(fridaModule.flavor, 'zygisk');
    expect(fridaModule.exportFileName, 'JsxposedxFrida.zip');
  });

  test('isZygisk is true for zygisk category', () {
    expect(fridaModule.isZygisk, isTrue);
  });

  test('isZygisk is false for non-zygisk category', () {
    const other = BundledModule(
      id: 'x',
      name: 'x',
      version: '',
      versionCode: 0,
      author: '',
      description: '',
      category: 'riru',
      flavor: 'riru',
      rootPath: 'a',
      requiredAssets: [],
      optionalAssets: [],
      exportFileName: 'x.zip',
    );
    expect(other.isZygisk, isFalse);
  });
}
