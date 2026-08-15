package com.jsxposed.x.core.bridge.apk_analysis_native

import org.jf.baksmali.Baksmali
import org.jf.baksmali.BaksmaliOptions
import org.jf.dexlib2.DexFileFactory
import org.jf.dexlib2.Opcodes
import org.jf.smali.Smali
import org.jf.smali.SmaliOptions
import java.io.File
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
 * APK (unsigned — no re-signing is performed). The pipeline is:
 *
 *   1. Extract each `classes*.dex` from the APK.
 *   2. Use baksmali to disassemble the dex into a smali directory.
 *   3. Locate the target class's `.smali` file and replace the target method's
 *      block with the AI-provided complete smali.
 *   4. Use smali to reassemble the smali directory back into a dex.
 *   5. Rebuild the APK, swapping the patched dex entry in place (no signing).
 */
object SmaliPatcher {

    /**
     * Apply the given modifications to [apkPath]. Returns the path of the
     * produced (unsigned) APK, or throws on failure.
     *
     * [workDir] is a writable directory (e.g. the app cache dir) used for the
     * intermediate smali/dex files and the output APK.
     *
     * Each modification names a `dexPath`, but the target class may actually
     * live in a different dex (classes.dex / classes2.dex / ...). To be
     * robust, we auto-detect which dex contains each class and patch the dex
     * where the class actually resides.
     */
    fun apply(apkPath: String, modifications: List<SmaliModification>, workDir: File = File(System.getProperty("java.io.tmpdir") ?: ".")): SmaliPatchResult {
        if (modifications.isEmpty()) {
            return SmaliPatchResult(apkPath, false, "没有要应用的修改")
        }
        val src = File(apkPath)
        if (!src.exists()) {
            return SmaliPatchResult(apkPath, false, "APK 文件不存在: $apkPath")
        }

        workDir.mkdirs()
        val output = File(workDir, "modified_${src.name}")

        return try {
            // 1. Determine, for each class, which dex entry actually contains it.
            val dexForClass = detectDexContainingClass(apkPath, modifications)

            // 2. Group modifications by the *resolved* dex entry.
            val byDex = HashMap<String, MutableList<SmaliModification>>()
            for (mod in modifications) {
                val dex = dexForClass[mod.className] ?: mod.dexPath
                byDex.getOrPut(dex) { mutableListOf() }.add(mod)
            }

            // 3. Rewrite the APK, patching the dex files that have changes.
            val srcZip = ZipFile(src)
            val outZip = ZipOutputStream(output.outputStream().buffered())

            srcZip.use { zin ->
                outZip.use { zout ->
                    val entries = zin.entries()
                    while (entries.hasMoreElements()) {
                        val entry = entries.nextElement()
                        val name = entry.name

                        if (name.endsWith(".dex") && byDex.containsKey(name)) {
                            val patchedDex = patchDexEntry(
                                zin.getInputStream(entry), byDex[name]!!, workDir, name,
                            )
                            zout.putNextEntry(ZipEntry(name))
                            patchedDex.inputStream().use { it.copyTo(zout) }
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

            SmaliPatchResult(output.absolutePath, true, "修改成功，输出未签名 APK")
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
                    zip.getInputStream(entry).use { input ->
                        dexFile.outputStream().use { input.copyTo(it) }
                    }
                    val dex = DexFileFactory.loadDexFile(dexFile, Opcodes.getDefault())
                    val present = dex.classes.map { it.type }.toHashSet()
                    for ((cls, desc) in descriptorByClass) {
                        if (present.contains(desc) && !result.containsKey(cls)) {
                            result[cls] = entry.name
                        }
                    }
                } catch (_: Exception) {
                    // If a dex can't be parsed, ignore and continue.
                } finally {
                    dexFile.delete()
                }
                // Stop early if all classes are located.
                if (result.size == descriptorByClass.size) break
            }
        }
        return result
    }

    private fun patchDexEntry(
        dexInput: java.io.InputStream,
        mods: List<SmaliModification>,
        workDir: File,
        dexEntryName: String,
    ): File {
        val safeName = dexEntryName.replace('/', '_')
        val dexFile = File(workDir, "${safeName}.in")
        dexFile.outputStream().use { dexInput.copyTo(it) }

        val smaliDir = File(workDir, "${safeName}_smali")
        smaliDir.mkdirs()

        // Disassemble the dex to smali.
        val dex = DexFileFactory.loadDexFile(dexFile, Opcodes.getDefault())
        val options = BaksmaliOptions()
        val ok = Baksmali.disassembleDexFile(dex, smaliDir, 1, options)
        if (!ok) {
            throw IllegalStateException("baksmali 反汇编失败: $dexEntryName")
        }

        // Apply each modification.
        for (mod in mods) {
            applyOne(smaliDir, mod)
        }

        // Reassemble smali back to dex.
        val outDex = File(workDir, "${safeName}.out")
        val smaliOpts = SmaliOptions().apply {
            outputDexFile = outDex.absolutePath
            apiLevel = 15
        }
        val assembleOk = Smali.assemble(smaliOpts, listOf(smaliDir.absolutePath))
        if (!assembleOk || !outDex.exists()) {
            throw IllegalStateException("smali 汇编失败: $dexEntryName")
        }
        return outDex
    }

    private fun applyOne(smaliDir: File, mod: SmaliModification) {
        val classSmali = findClassSmaliFile(smaliDir, mod.className)
            ?: throw IllegalStateException("未找到类 ${mod.className} 的 smali 文件")

        val content = classSmali.readText()

        // Find the method block for mod.methodName and replace it.
        val descriptor = methodDescriptor(content, mod.methodName)
            ?: throw IllegalStateException("类 ${mod.className} 中未找到方法 ${mod.methodName}")

        // Replace the block starting at this method's `.method` line through its
        // matching `.end method`.
        val newContent = replaceMethodBlock(content, descriptor, mod.modifiedSmali)
        classSmali.writeText(newContent)
    }

    /** Locate the smali file for a fully qualified class name. */
    private fun findClassSmaliFile(smaliDir: File, className: String): File? {
        // Class name may contain '$' for inner classes.
        val parts = className.split('.')
        val fileName = parts.last() + ".smali"
        val dirs = parts.dropLast(1)

        // Direct path: smali/package/path/Name.smali
        val direct = File(File(smaliDir, dirs.joinToString("/")), fileName)
        if (direct.exists()) return direct

        // Fallback 1: recursive search by filename (handles package mismatches).
        val byName = smaliDir.walkTopDown().firstOrNull { it.isFile && it.name == fileName }
        if (byName != null) return byName

        // Fallback 2: search for a smali file whose first line declares this
        // class descriptor (e.g. `.class public Lcom/duapps/recorder/mb0;`).
        // This is the most reliable match even when the filename is obfuscated
        // or differs from the class name.
        val descriptor = "L${className.replace('.', '/')};"
        return smaliDir.walkTopDown().firstOrNull { file ->
            if (!file.isFile || !file.name.endsWith(".smali")) return@firstOrNull false
            try {
                val head = file.useLines { lines ->
                    lines.take(50).joinToString("\n")
                }
                head.contains(descriptor)
            } catch (_: Exception) {
                false
            }
        }
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
        // .method public abstract isVip()Z  -> isVip
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
                // Consume until the matching .end method.
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
                // Insert the replacement smali (normalize line endings).
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
