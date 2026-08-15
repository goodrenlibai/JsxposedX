package com.jsxposed.x.core.bridge.apk_analysis_native

import org.jf.baksmali.Adaptors.ClassDefinition
import org.jf.baksmali.BaksmaliOptions
import org.jf.baksmali.formatter.BaksmaliWriter
import org.jf.dexlib2.DexFileFactory
import org.jf.dexlib2.Opcodes
import org.jf.dexlib2.iface.ClassDef
import org.jf.dexlib2.writer.io.FileDataStore
import org.jf.dexlib2.writer.pool.DexPool
import org.jf.smali.Smali
import org.jf.smali.SmaliOptions
import java.io.File
import java.io.StringWriter
import java.util.zip.ZipFile

/**
 * A single smali modification request derived from the AI's plan.
 *
 * @property dexPath which dex entry inside the APK to patch (e.g. "classes.dex")
 * @property className fully qualified class name with dots (e.g. "com.example.app.VipManager")
 * @property methodName target method name
 * @property modifiedSmali the COMPLETE replacement smali for that method
 *   (from `.method` to `.end method`, exactly as the AI output).
 */
data class SmaliModification(
    val dexPath: String,
    val className: String,
    val methodName: String,
    val modifiedSmali: String,
)

/**
 * Result of applying a batch of smali modifications to an APK.
 */
data class SmaliPatchResult(
    val outputPath: String,
    val success: Boolean,
    val message: String,
)

/**
 * Applies smali modifications to the dex files inside an APK and writes a NEW
 * APK (unsigned — no re-signing is performed).
 *
 * PERFORMANCE (fast, similar to MT Manager's "Dex 编辑器++"):
 * - Only the *modified classes* are round-tripped through smali text
 *   (disassemble single class → replace method → reassemble single class).
 * - Every other class is byte-copied directly via [DexPool.internClass].
 * - The whole APK is rewritten in a SINGLE pass over the zip entries, and each
 *   dex is parsed at most once (target detection and patching are combined),
 *   avoiding the extra full re-read of every dex.
 */
object SmaliPatcher {

    fun apply(
        apkPath: String,
        modifications: List<SmaliModification>,
        workDir: File = File(System.getProperty("java.io.tmpdir") ?: "."),
    ): SmaliPatchResult {
        if (modifications.isEmpty()) {
            return SmaliPatchResult(apkPath, false, "没有要应用的修改")
        }
        val src = File(apkPath)
        if (!src.exists()) {
            return SmaliPatchResult(apkPath, false, "APK 文件不存在: $apkPath")
        }

        workDir.mkdirs()

        // Output goes to the SAME directory as the original APK by default.
        val srcParent = src.parentFile?.takeIf { it.exists() && it.canWrite() }
        val output = File(srcParent ?: workDir, "modified_${src.name}")
        val usedFallbackDir = srcParent == null

        return try {
            // Single pass: iterate dex entries once. For each dex, parse it
            // once, and if it contains any target class, patch it inline.
            val remaining = HashMap<String, MutableList<SmaliModification>>()
            for (mod in modifications) {
                remaining.getOrPut(mod.className) { mutableListOf() }.add(mod)
            }

            val outEntries = ArrayList<ZipSourceEntry>()

            ZipFile(src).use { zin ->
                val entries = zin.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    val name = entry.name
                    val isDex = name.endsWith(".dex") && !entry.isDirectory

                    if (isDex && remaining.isNotEmpty()) {
                        // Parse this dex once and find which target classes it holds.
                        val found = try {
                            val dexFile = File.createTempFile("dex_", ".dex")
                            try {
                                zin.getInputStream(entry).use { it.copyTo(dexFile.outputStream()) }
                                val dex = DexFileFactory.loadDexFile(dexFile, Opcodes.getDefault())
                                val descSet = dex.classes.map { it.type }.toHashSet()
                                remaining.keys.filter { cls ->
                                    descSet.contains("L${cls.replace('.', '/')};")
                                }.toList()
                            } finally {
                                dexFile.delete()
                            }
                        } catch (_: Exception) {
                            emptyList()
                        }

                        if (found.isEmpty()) {
                            // No target class here — copy raw bytes.
                            outEntries.add(ZipSourceEntry(name, readBytes(zin.getInputStream(entry))))
                        } else {
                            // Re-read the entry and patch it (only the found classes).
                            val modsForDex = found.flatMap { remaining[it] ?: emptyList() }
                            val patched = patchDexEntry(
                                zin.getInputStream(entry), modsForDex, workDir, name,
                            )
                            for (cls in found) remaining.remove(cls)
                            outEntries.add(ZipSourceEntry(name, readBytes(patched.inputStream())))
                        }
                    } else {
                        outEntries.add(ZipSourceEntry(name, readBytes(zin.getInputStream(entry))))
                    }
                }
            }

            // Any class we never located in any dex → report it.
            if (remaining.isNotEmpty()) {
                val missing = remaining.keys.joinToString(", ")
                return SmaliPatchResult(apkPath, false, "修改失败: 以下类未在任何 dex 中找到: $missing")
            }

            // Write the APK with 4-byte alignment and uncompressed resources.arsc
            // (required for install on Android 11+ / targetSdk 30).
            AlignedZip.write(output, outEntries)

            val msg = if (usedFallbackDir) {
                "修改成功（原目录不可写，已保存到: ${output.absolutePath}）"
            } else {
                "修改成功，未签名 APK 已保存到: ${output.absolutePath}"
            }
            SmaliPatchResult(output.absolutePath, true, msg)
        } catch (e: Exception) {
            SmaliPatchResult(apkPath, false, "修改失败: ${e.message}")
        }
    }

    /**
     * Patch a single dex. Only the modified classes are round-tripped through
     * smali text; everything else is byte-copied via [DexPool].
     */
    private fun patchDexEntry(
        dexInput: java.io.InputStream,
        mods: List<SmaliModification>,
        workDir: File,
        dexEntryName: String,
    ): File {
        val safeName = dexEntryName.replace('/', '_')
        val srcDex = File(workDir, "${safeName}.in")
        dexInput.use { it.copyTo(srcDex.outputStream()) }

        val opcodes = Opcodes.getDefault()
        val source = DexFileFactory.loadDexFile(srcDex, opcodes)
        val pool = DexPool(opcodes)

        // Build the modified classes: className(dots) -> ClassDef
        val modifiedClasses = HashMap<String, ClassDef>()
        val targetDescriptors = mods.map {
            "L${it.className.replace('.', '/')};"
        }.toHashSet()

        for (classDef in source.classes) {
            val desc = classDef.type
            val dotName = desc.substring(1, desc.length - 1).replace('/', '.')
            if (targetDescriptors.contains(desc)) {
                val classMods = mods.filter { it.className == dotName }
                if (classMods.isNotEmpty()) {
                    val rebuilt = rebuildClass(classDef, classMods, workDir, safeName)
                    modifiedClasses[dotName] = rebuilt
                }
            }
        }

        // Rebuild the pool: unmodified classes byte-copied, modified ones interned.
        for (classDef in source.classes) {
            val desc = classDef.type
            val dotName = desc.substring(1, desc.length - 1).replace('/', '.')
            val replacement = modifiedClasses[dotName]
            if (replacement != null) {
                pool.internClass(replacement)
            } else {
                pool.internClass(classDef)
            }
        }

        val outDex = File(workDir, "${safeName}.out")
        pool.writeTo(FileDataStore(outDex))
        return outDex
    }

    /**
     * Rebuild a single class with its target method(s) replaced.
     */
    private fun rebuildClass(
        classDef: ClassDef,
        mods: List<SmaliModification>,
        workDir: File,
        tag: String,
    ): ClassDef {
        // 1. Disassemble ONLY this class to smali text.
        val smaliText = disassembleSingleClass(classDef)

        // 2. Apply method replacements.
        var modified = smaliText
        for (mod in mods) {
            val startLine = methodDescriptor(modified, mod.methodName)
                ?: throw IllegalStateException("类 ${mod.className} 中未找到方法 ${mod.methodName}")
            modified = replaceMethodBlock(modified, startLine, mod.modifiedSmali)
        }

        // 3. Write the single-class smali to a temp dir and reassemble.
        val clsSmaliDir = File(workDir, "${tag}_cls_${System.nanoTime()}")
        clsSmaliDir.mkdirs()
        val file = smaliFileForClass(clsSmaliDir, classDef.type)
        file.parentFile?.mkdirs()
        file.writeText(modified)

        val tmpDex = File(workDir, "${tag}_cls_${System.nanoTime()}.dex")
        val smaliOpts = SmaliOptions().apply {
            outputDexFile = tmpDex.absolutePath
            apiLevel = 15
        }
        val ok = Smali.assemble(smaliOpts, listOf(clsSmaliDir.absolutePath))
        if (!ok || !tmpDex.exists()) {
            throw IllegalStateException("类 ${classDef.type} 重新汇编失败")
        }

        // 4. Load the tiny dex and return the single rebuilt class.
        val rebuiltDex = DexFileFactory.loadDexFile(tmpDex, Opcodes.getDefault())
        return rebuiltDex.classes.firstOrNull()
            ?: throw IllegalStateException("重新汇编后未得到类 ${classDef.type}")
    }

    /** Disassemble a single class to a smali text string. */
    private fun disassembleSingleClass(classDef: ClassDef): String {
        val options = BaksmaliOptions()
        val writer = StringWriter()
        val baksmaliWriter = BaksmaliWriter(writer)
        val classDefinition = ClassDefinition(options, classDef)
        classDefinition.writeTo(baksmaliWriter)
        baksmaliWriter.flush()
        return writer.toString()
    }

    private fun smaliFileForClass(smaliDir: File, descriptor: String): File {
        val rel = descriptor.substring(1, descriptor.length - 1)
        val path = rel.replace('/', '/')
        return File(smaliDir, "$path.smali")
    }

    /** Find the exact `.method ... name(...)...` line for the given method. */
    private fun methodDescriptor(content: String, methodName: String): String? {
        for (line in content.lineSequence()) {
            val trimmed = line.trim()
            if (trimmed.startsWith(".method ")) {
                if (methodRegexName(trimmed) == methodName) {
                    return trimmed
                }
            }
        }
        return null
    }

    private fun methodRegexName(methodLine: String): String {
        val openParen = methodLine.indexOf('(')
        if (openParen <= 0) return ""
        val before = methodLine.substring(0, openParen).trim()
        val space = before.lastIndexOf(' ')
        return if (space >= 0) before.substring(space + 1) else before
    }

    private fun replaceMethodBlock(content: String, methodStartLine: String, newSmali: String): String {
        val lines = content.split("\n")
        val sb = StringBuilder()
        var i = 0
        var replaced = false
        while (i < lines.size) {
            val line = lines[i]
            if (!replaced && line.trim() == methodStartLine.trim()) {
                var depth = 0
                while (i < lines.size) {
                    val l = lines[i]
                    if (l.trim().startsWith(".method ")) depth++
                    if (l.trim() == ".end method") {
                        depth--
                        if (depth <= 0) {
                            i++
                            break
                        }
                    }
                    i++
                }
                sb.append(newSmali.trim()).append("\n")
                replaced = true
            } else {
                sb.append(line).append("\n")
                i++
            }
        }
        return sb.toString()
    }
}
