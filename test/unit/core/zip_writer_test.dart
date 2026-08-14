import 'dart:convert';
import 'dart:typed_data';

import 'package:JsxposedX/core/utils/zip_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal ZIP central-directory reader used only for verification inside the
/// test (keeps the suite self-contained / offline).
class _ZipProbe {
  final int entryCount;
  final List<String> names;
  final List<int> methods;
  final int localHeaderOffset;

  _ZipProbe(this.entryCount, this.names, this.methods, this.localHeaderOffset);

  static _ZipProbe parse(Uint8List bytes) {
    // Locate End Of Central Directory record.
    int eocd = -1;
    for (int i = bytes.lengthInBytes - 22; i >= 0; i--) {
      if (_u32(bytes, i) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    expect(eocd, greaterThanOrEqualTo(0), reason: 'EOCD signature found');

    final totalEntries = _u16(bytes, eocd + 10);
    final centralSize = _u32(bytes, eocd + 12);
    final centralOffset = _u32(bytes, eocd + 16);

    final names = <String>[];
    final methods = <int>[];
    var p = centralOffset;
    for (var i = 0; i < totalEntries; i++) {
      expect(_u32(bytes, p), 0x02014b50, reason: 'central dir sig $i');
      final method = _u16(bytes, p + 10);
      final nameLen = _u16(bytes, p + 28);
      final name = utf8.decode(
        bytes.sublist(p + 46, p + 46 + nameLen),
      );
      names.add(name);
      methods.add(method);
      p += 46 + nameLen;
    }
    expect(p, centralOffset + centralSize, reason: 'central dir consumed fully');
    return _ZipProbe(totalEntries, names, methods, centralOffset);
  }
}

int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _u32(Uint8List b, int o) => _u16(b, o) | (_u16(b, o + 2) << 16);

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
Uint8List _raw(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group('ZipWriter.write structure', () {
    test('empty archive is valid and has no entries', () {
      final zip = ZipWriter.write(entries: const []);
      expect(zip, isNotEmpty);
      // With no entries the archive is just the EOCD record.
      expect(_u32(zip, 0), 0x06054b50);
      final probe = _ZipProbe.parse(zip);
      expect(probe.entryCount, 0);
      expect(probe.names, isEmpty);
    });

    test('single file archive exposes that file', () {
      final zip = ZipWriter.write(entries: [
        ZipEntryData(path: 'module.prop', bytes: _bytes('id=test\n')),
      ]);
      final probe = _ZipProbe.parse(zip);
      expect(probe.entryCount, 1);
      expect(probe.names, ['module.prop']);
      expect(probe.methods, [0]); // STORE
      expect(_u32(zip, 0), 0x04034b50);
    });

    test('multiple nested files are all recorded', () {
      final zip = ZipWriter.write(entries: [
        ZipEntryData(path: 'module.prop', bytes: _bytes('id=x')),
        ZipEntryData(path: 'lib/arm64-v8a.so', bytes: _raw([1, 2, 3, 4])),
        ZipEntryData(path: 'META-INF/com/google/android/update-binary',
            bytes: _bytes('#!/sbin/sh')),
        ZipEntryData(path: 'lib/arm64-v8a.so.sha256sum', bytes: _bytes('abc\n')),
      ]);
      final probe = _ZipProbe.parse(zip);
      expect(probe.entryCount, 4);
      expect(probe.names, containsAll([
        'module.prop',
        'lib/arm64-v8a.so',
        'META-INF/com/google/android/update-binary',
        'lib/arm64-v8a.so.sha256sum',
      ]));
    });

    test('duplicate paths keep both entries', () {
      final zip = ZipWriter.write(entries: [
        ZipEntryData(path: 'a.txt', bytes: _bytes('one')),
        ZipEntryData(path: 'a.txt', bytes: _bytes('two')),
      ]);
      final probe = _ZipProbe.parse(zip);
      expect(probe.entryCount, 2);
      expect(probe.names.where((n) => n == 'a.txt').length, 2);
    });

    test('binary payload is embedded verbatim', () {
      final payload = Uint8List.fromList(List<int>.generate(512, (i) => i % 251));
      final zip = ZipWriter.write(entries: [
        ZipEntryData(path: 'bin.dat', bytes: payload),
      ]);
      // The local header (30 bytes + 7 name bytes) precedes the payload.
      final dataStart = 30 + 'bin.dat'.length;
      final extracted = zip.sublist(dataStart, dataStart + payload.length);
      expect(extracted, payload);
    });
  });

  group('ZipWriter determinism & UTF-8', () {
    test('same inputs produce identical bytes', () {
      final entries = [
        ZipEntryData(path: 'x.prop', bytes: _bytes('hello')),
      ];
      final a = ZipWriter.write(entries: entries);
      final b = ZipWriter.write(entries: entries);
      expect(a, b);
    });

    test('non-ASCII filenames round-trip (UTF-8 flag set)', () {
      final name = 'gadget/libgadget-中文.so.xz';
      final zip = ZipWriter.write(entries: [
        ZipEntryData(path: name, bytes: _bytes('data')),
      ]);
      final probe = _ZipProbe.parse(zip);
      expect(probe.names, [name]);
    });
  });
}
