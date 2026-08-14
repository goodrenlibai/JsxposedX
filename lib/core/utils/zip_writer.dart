import 'dart:typed_data';

/// A single entry (file) that will be written into a ZIP archive.
class ZipEntryData {
  const ZipEntryData({
    required this.path,
    required this.bytes,
  });

  /// Archive-relative path (forward slashes). e.g. `module.prop`, `lib/x86.so`
  final String path;

  /// Raw file content.
  final Uint8List bytes;
}

/// A minimal, dependency-free ZIP writer using the STORE (no-compression)
/// method. The ZIP format produced here is fully valid and can be consumed by
/// `unzip`, Magisk Manager and TWRP's zip installer, which is enough for a
/// Magisk module package.
///
/// Why STORE instead of DEFLATE?
///   - No external compression dependency (keeps the app self-contained).
///   - Magisk modules are mostly already-compressed binaries (e.g. `.so.xz`),
///     so DEFLATE would provide little benefit.
///
/// The writer always uses the ZIP64-unaware classic structure, which is fine
/// because individual entries and the total archive stay below 4 GiB for our
/// module payloads.
class ZipWriter {
  ZipWriter._();

  static Uint8List write({
    required Iterable<ZipEntryData> entries,
  }) {
    final localParts = <Uint8List>[];
    final centralParts = <Uint8List>[];
    var offset = 0;

    for (final entry in entries) {
      final nameBytes = Uint8List.fromList(_utf8(entry.path));
      final data = entry.bytes;
      final crc = _crc32(data);

      final local = ByteData(30);
      _writeU32(local, 0, 0x04034b50); // local file header signature
      _writeU16(local, 4, 20); // version needed to extract
      _writeU16(local, 6, 0x0800); // UTF-8 filename flag
      _writeU16(local, 8, 0); // compression method: STORE
      _writeU16(local, 10, 0); // mod time
      _writeU16(local, 12, 0x21); // mod date (fixed)
      _writeU32(local, 14, crc);
      _writeU32(local, 18, data.lengthInBytes); // compressed size
      _writeU32(local, 22, data.lengthInBytes); // uncompressed size
      _writeU16(local, 26, nameBytes.lengthInBytes);
      _writeU16(local, 28, 0); // extra field length

      final localBytes = Uint8List(30 + nameBytes.lengthInBytes);
      localBytes.setRange(0, 30, local.buffer.asUint8List());
      localBytes.setRange(30, 30 + nameBytes.lengthInBytes, nameBytes);
      localParts.add(localBytes);
      localParts.add(data);

      final central = ByteData(46);
      _writeU32(central, 0, 0x02014b50); // central directory signature
      _writeU16(central, 4, 20); // version made by
      _writeU16(central, 6, 20); // version needed
      _writeU16(central, 8, 0x0800); // UTF-8 flag
      _writeU16(central, 10, 0); // method
      _writeU16(central, 12, 0); // time
      _writeU16(central, 14, 0x21); // date
      _writeU32(central, 16, crc);
      _writeU32(central, 20, data.lengthInBytes);
      _writeU32(central, 24, data.lengthInBytes);
      _writeU16(central, 28, nameBytes.lengthInBytes);
      _writeU16(central, 30, 0); // extra len
      _writeU16(central, 32, 0); // comment len
      _writeU16(central, 34, 0); // disk start
      _writeU16(central, 36, 0); // internal attrs
      _writeU32(central, 38, 0); // external attrs
      _writeU32(central, 42, offset); // local header offset

      final centralBytes = Uint8List(46 + nameBytes.lengthInBytes);
      centralBytes.setRange(0, 46, central.buffer.asUint8List());
      centralBytes.setRange(
        46,
        46 + nameBytes.lengthInBytes,
        nameBytes,
      );
      centralParts.add(centralBytes);

      offset += localBytes.lengthInBytes + data.lengthInBytes;
    }

    final centralSize = centralParts.fold<int>(
      0,
      (sum, part) => sum + part.lengthInBytes,
    );

    final eocd = ByteData(22);
    _writeU32(eocd, 0, 0x06054b50); // end of central directory signature
    _writeU16(eocd, 4, 0); // disk number
    _writeU16(eocd, 6, 0); // disk with central directory
    _writeU16(eocd, 8, entries.length); // entries on this disk
    _writeU16(eocd, 10, entries.length); // total entries
    _writeU32(eocd, 12, centralSize);
    _writeU32(eocd, 16, offset);
    _writeU16(eocd, 20, 0); // comment length

    final total = offset + centralSize + 22;
    final out = Uint8List(total);
    var cursor = 0;
    for (final part in localParts) {
      out.setRange(cursor, cursor + part.lengthInBytes, part);
      cursor += part.lengthInBytes;
    }
    for (final part in centralParts) {
      out.setRange(cursor, cursor + part.lengthInBytes, part);
      cursor += part.lengthInBytes;
    }
    out.setRange(cursor, cursor + 22, eocd.buffer.asUint8List());
    return out;
  }

  static Uint8List _utf8(String value) {
    return Uint8List.fromList(value.codeUnits);
  }

  static void _writeU16(ByteData data, int offset, int value) {
    data.setUint16(offset, value, Endian.little);
  }

  static void _writeU32(ByteData data, int offset, int value) {
    data.setUint32(offset, value, Endian.little);
  }

  /// CRC-32 (IEEE 802.3) with a cached lookup table.
  static final Uint32List _crcTable = _buildCrcTable();
  static Uint32List _buildCrcTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    return table;
  }

  static int _crc32(Uint8List data) {
    var crc = 0xffffffff;
    for (var i = 0; i < data.lengthInBytes; i++) {
      crc = _crcTable[(crc ^ data[i]) & 0xff] ^ (crc >> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}
