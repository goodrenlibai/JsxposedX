import 'package:JsxposedX/core/utils/format_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDurationShort', () {
    test('sub-minute durations render as seconds', () {
      expect(formatDurationShort(0), '0s');
      expect(formatDurationShort(999), '0s');
      expect(formatDurationShort(59000), '59s');
    });

    test('minute-level durations render as "Xm Ys"', () {
      expect(formatDurationShort(60000), '1m 0s');
      expect(formatDurationShort(61000), '1m 1s');
      expect(formatDurationShort(119999), '1m 59s');
      expect(formatDurationShort(120000), '2m 0s');
    });

    test('boundary: exactly 60s flips to minutes', () {
      expect(formatDurationShort(59999), '59s');
      expect(formatDurationShort(60000), '1m 0s');
    });

    test('does not crash on negative input', () {
      expect(() => formatDurationShort(-1), returnsNormally);
    });
  });

  group('formatBytesCompact', () {
    test('byte-range values', () {
      expect(formatBytesCompact(0), '0 B');
      expect(formatBytesCompact(1023), '1023 B');
    });

    test('kilobyte-range values', () {
      expect(formatBytesCompact(1024), '1.0 KB');
      expect(formatBytesCompact(1536), '1.5 KB');
      expect(formatBytesCompact(1048575), '1024.0 KB');
    });

    test('megabyte-range values', () {
      expect(formatBytesCompact(1048576), '1.0 MB');
      expect(formatBytesCompact(3145728), '3.0 MB');
    });

    test('boundary: exactly 1 MiB flips to MB', () {
      expect(formatBytesCompact(1048575), '1024.0 KB');
      expect(formatBytesCompact(1048576), '1.0 MB');
    });
  });
}
