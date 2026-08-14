import 'package:JsxposedX/features/modules/domain/models/module_export_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ModuleExportResult.ok carries success data', () {
    final r = ModuleExportResult.ok(
      moduleId: 'm1',
      outputPath: '/tmp/m1.zip',
      bytesWritten: 1234,
      warnings: ['warning'],
    );
    expect(r.success, isTrue);
    expect(r.moduleId, 'm1');
    expect(r.outputPath, '/tmp/m1.zip');
    expect(r.bytesWritten, 1234);
    expect(r.warnings, ['warning']);
  });

  test('ModuleExportResult.fail carries error', () {
    final r = ModuleExportResult.fail(
      moduleId: 'm1',
      error: 'boom',
      warnings: ['w'],
    );
    expect(r.success, isFalse);
    expect(r.error, 'boom');
    expect(r.outputPath, isNull);
    expect(r.bytesWritten, isNull);
  });

  test('ModuleExportResult.ok defaults warnings to empty', () {
    final r = ModuleExportResult.ok(
      moduleId: 'm1',
      outputPath: '/tmp/m1.zip',
      bytesWritten: 0,
    );
    expect(r.warnings, isEmpty);
  });
}
