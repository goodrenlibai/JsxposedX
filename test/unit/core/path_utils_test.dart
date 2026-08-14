import 'package:JsxposedX/core/utils/path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PathUtils.getName', () {
    test('returns the last path segment', () {
      expect(PathUtils.getName(path: '/a/b/c.js'), 'c.js');
      expect(PathUtils.getName(path: 'single.js'), 'single.js');
      expect(PathUtils.getName(path: '/root'), 'root');
    });

    test('handles trailing slash', () {
      expect(PathUtils.getName(path: '/a/b/'), '');
    });

    test('isXposedScript strips [tag] suffix', () {
      expect(
        PathUtils.getName(path: '/scripts/[hook]main.js', isXposedScript: true),
        'main.js',
      );
      expect(
        PathUtils.getName(path: '[log]trace.js', isXposedScript: true),
        'trace.js',
      );
      expect(
        PathUtils.getName(path: 'plain.js', isXposedScript: true),
        'plain.js',
      );
    });

    test('isXposedScript=false keeps brackets', () {
      expect(
        PathUtils.getName(path: '/scripts/[hook]main.js', isXposedScript: false),
        '[hook]main.js',
      );
    });
  });

  group('PathUtils.getType', () {
    test('extracts bracket tag', () {
      expect(PathUtils.getType('[hook]main.js'), 'hook');
      expect(PathUtils.getType('[log]trace.js'), 'log');
    });

    test('returns null when no bracket', () {
      expect(PathUtils.getType('main.js'), isNull);
    });

    test('returns first bracket group', () {
      expect(PathUtils.getType('pre[hook]post.js'), 'hook');
    });
  });
}
