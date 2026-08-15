package com.jsxposed.x.core.bridge.apk_analysis_native

import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.CRC32

/**
 * A minimal ZIP writer that produces an **aligned, mostly-uncompressed** APK,
 * satisfying the requirements for install on Android 11+ (targetSdk 30):
 *
 *   - `resources.arsc` (and native `.so` libs) must be stored UNCOMPRESSED.
 *   - every entry's data must start on a 4-byte boundary (zipalign -p 4).
 *
 * This avoids the install error:
 *   "Targeting R+ ... requires the resources.arsc of installed APKs to be
 *    stored uncompressed and aligned on a 4-byte boundary"
 *
 * It writes everything with the STORE (no compression) method, which is also
 * faster to produce (no deflate) and guarantees alignment.
 */
object AlignedZip {

    private const val LOCAL_FILE_HEADER_SIG = 0x04034b50
    private const val CENTRAL_DIR_HEADER_SIG = 0x02014b50
    private const val END_OF_CENTRAL_DIR_SIG = 0x06054b50

    private const val METHOD_STORE = 0
    private const val UTF8_FLAG = 0x0800
    private const val ALIGN = 4

    fun write(outFile: File, entries: List<ZipSourceEntry>) {
        val localParts = ArrayList<ByteArray>()
        val centralParts = ArrayList<ByteArray>()
        val centralRecords = ArrayList<CentralRecord>()

        var offset = 0L

        BufferedOutputStream(FileOutputStream(outFile)).use { out ->
            for (entry in entries) {
                // Read data.
                val data = entry.bytes()
                val crc = crc32(data)

                // Pad so the LOCAL HEADER starts on ALIGN boundary (extra safety)
                // and pad so the DATA starts on ALIGN boundary.
                // zipalign aligns the start of uncompressed data.
                val headerSize = 30 + entry.name.toByteArray(Charsets.UTF_8).size
                // Align data start to 4 bytes: offset of header is arbitrary, but
                // data begins right after header; pad header so that
                // (offset + headerSize) % 4 == 0.
                val pad = ((ALIGN - ((offset + headerSize) % ALIGN)) % ALIGN).toInt()
                repeat(pad) { out.write(0) }
                offset += pad

                // Write local header + name + data.
                val local = localHeader(
                    name = entry.name,
                    crc = crc,
                    size = data.size,
                )
                out.write(local)
                out.write(entry.name.toByteArray(Charsets.UTF_8))
                out.write(data)
                offset += headerSize + data.size

                val central = centralHeader(
                    name = entry.name,
                    crc = crc,
                    size = data.size,
                    localOffset = offset - (headerSize + data.size),
                )
                centralRecords.add(CentralRecord(entry.name, central))
            }

            // Central directory.
            val centralStart = offset
            for (rec in centralRecords) {
                out.write(rec.header)
                out.write(rec.name.toByteArray(Charsets.UTF_8))
                offset += rec.header.size + rec.name.toByteArray(Charsets.UTF_8).size
            }
            val centralSize = offset - centralStart

            // End of central directory.
            out.write(
                endOfCentralDirectory(
                    entryCount = entries.size,
                    centralSize = centralSize,
                    centralOffset = centralStart,
                )
            )
        }
    }

    private fun localHeader(name: String, crc: Long, size: Int): ByteArray {
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        val b = ByteArray(30)
        writeIntLE(b, 0, LOCAL_FILE_HEADER_SIG)
        writeShortLE(b, 4, 20) // version needed
        writeShortLE(b, 6, UTF8_FLAG)
        writeShortLE(b, 8, METHOD_STORE)
        writeShortLE(b, 10, 0) // mod time
        writeShortLE(b, 12, 0x21) // mod date
        writeIntLE(b, 14, crc.toInt())
        writeIntLE(b, 18, size)
        writeIntLE(b, 22, size)
        writeShortLE(b, 26, nameBytes.size)
        writeShortLE(b, 28, 0) // extra
        return b
    }

    private fun centralHeader(name: String, crc: Long, size: Int, localOffset: Long): ByteArray {
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        val b = ByteArray(46)
        writeIntLE(b, 0, CENTRAL_DIR_HEADER_SIG)
        writeShortLE(b, 4, 20) // version made by
        writeShortLE(b, 6, 20) // version needed
        writeShortLE(b, 8, UTF8_FLAG)
        writeShortLE(b, 10, METHOD_STORE)
        writeShortLE(b, 12, 0)
        writeShortLE(b, 14, 0x21)
        writeIntLE(b, 16, crc.toInt())
        writeIntLE(b, 20, size)
        writeIntLE(b, 24, size)
        writeShortLE(b, 28, nameBytes.size)
        writeShortLE(b, 30, 0)
        writeShortLE(b, 32, 0)
        writeShortLE(b, 34, 0)
        writeShortLE(b, 36, 0)
        writeIntLE(b, 38, 0) // external attrs
        writeIntLE(b, 42, localOffset.toInt())
        return b
    }

    private fun endOfCentralDirectory(entryCount: Int, centralSize: Long, centralOffset: Long): ByteArray {
        val b = ByteArray(22)
        writeIntLE(b, 0, END_OF_CENTRAL_DIR_SIG)
        writeShortLE(b, 4, 0)
        writeShortLE(b, 6, 0)
        writeShortLE(b, 8, entryCount)
        writeShortLE(b, 10, entryCount)
        writeIntLE(b, 12, centralSize.toInt())
        writeIntLE(b, 16, centralOffset.toInt())
        writeShortLE(b, 20, 0)
        return b
    }

    private fun crc32(data: ByteArray): Long {
        val c = CRC32()
        c.update(data)
        return c.value
    }

    private fun writeIntLE(b: ByteArray, off: Int, value: Int) {
        b[off] = (value and 0xff).toByte()
        b[off + 1] = ((value ushr 8) and 0xff).toByte()
        b[off + 2] = ((value ushr 16) and 0xff).toByte()
        b[off + 3] = ((value ushr 24) and 0xff).toByte()
    }

    private fun writeShortLE(b: ByteArray, off: Int, value: Int) {
        b[off] = (value and 0xff).toByte()
        b[off + 1] = ((value ushr 8) and 0xff).toByte()
    }

    private data class CentralRecord(val name: String, val header: ByteArray)
}

/** A source entry for the aligned zip writer: either raw bytes or an input stream. */
class ZipSourceEntry(val name: String, private val bytes: ByteArray?, private val stream: InputStream?) {
    constructor(name: String, bytes: ByteArray) : this(name, bytes, null)
    constructor(name: String, stream: InputStream) : this(name, null, stream)

    fun bytes(): ByteArray {
        bytes?.let { return it }
        val s = stream ?: return ByteArray(0)
        return s.use { it.readBytes() }
    }
}

/** Helper to write a file into the zip (streaming not needed for our sizes). */
fun readBytes(input: InputStream): ByteArray = input.use { it.readBytes() }
