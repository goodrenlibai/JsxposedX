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
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

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
 * Instead of disassembling + reassembling the ENTIRE dex to/from smali text
 * (the naive approach, which is very slow), we only text-round-trip the
 * *modified class(es)*:
 *
 *   1. Load the source dex via dexlib2 ([DexFileFactory.loadDexFile]).
 *   2. For each target class: disassemble ONLY that class to smali text, apply
 *      the method replacement, then reassemble ONLY that class (via a tiny
 *      smali project) to obtain a modified [ClassDef].
 *   3. Build a [DexPool]: byte-copy every UNMODIFIED class directly
 *      ([DexPool.internClass]) and intern the modified class(es).
 *   4. Write the pool to the output dex.
 *
 * This keeps the bulk of the dex as a fast binary copy, which is why it's much
 * closer to MT Manager's speed.
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
            // 1. Determine which dex contains each target class.
            val dexForClass = detectDexContainingClass(apkPath, modifications)

            // 2. Group modifications by the resolved dex entry.
            val byDex = HashMap<String, MutableList<SmaliModification>>()
            for (mod in modifications) {
                val dex = dexForClass[mod.className] ?: mod.dexPath
                byDex.getOrPut(dex) { mutableListOf() }.add(mod)
            }

            // 3. Rewrite the APK, patching the dex files that have changes.
            ZipFile(src).use { zin ->
                ZipOutputStream(output.outputStream().buffered()).use { zout ->
                    val entries = zin.entries()
                    while (entries.hasMoreElements()) {
                        val entry = entries.nextElement()
                        val name = entry.name
                        if (name.endsWith(".dex") && byDex.containsKey(name)) {
                            val patched = patchDexEntry(
                                zin.getInputStream(entry), byDex[name]!!, workDir, name,
                            )
                            zout.putNextEntry(ZipEntry(name))
                            patched.inputStream().use { it.copyTo(zout) }
                            zout.closeEntry()
                        } else {
                            zout.putNextEntry(ZipEntry(name))
                            if (!entry.isDirectory) {
                                zin.getInputStream(entry).use { it.copyTo(zout) }
                            }
                            zout.closeEntry()
                        }
                    }
                }
            }
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

    /** Determine which dex entry contains each target class. */
    private fun detectDexContainingClass(
        apkPath: String,
        modifications: List<SmaliModification>,
    ): Map<String, String> {
        val result = HashMap<String, String>()
        val descriptorByClass = modifications.associate {
            it.className to "L${it.className.replace('.', '/')};"
        }
        ZipFile(apkPath).use { zip ->
            val dexEntries = zip.entries().asSequence()
                .filter { it.name.endsWith(".dex") && !it.isDirectory }
                .toList()
            for (entry in dexEntries) {
                val dexFile = File.createTempFile("probe_", ".dex")
                try {
                    zip.getInputStream(entry).use { it.copyTo(dexFile.outputStream()) }
                    val dex = DexFileFactory.loadDexFile(dexFile, Opcodes.getDefault())
                    val present = dex.classes.map { it.type }.toHashSet()
                    for ((cls, desc) in descriptorByClass) {
                        if (present.contains(desc) && !result.containsKey(cls)) {
                            result[cls] = entry.name
                        }
                    }
                } catch (_: Exception) {
                    // Ignore dex files that can't be parsed.
                } finally {
                    dexFile.delete()
                }
                if (result.size == descriptorByClass.size) break
            }
        }
        return result
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
