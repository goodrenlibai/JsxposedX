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
            // Group modifications by dex entry.
            val byDex = modifications.groupBy { it.dexPath }

            val srcZip = ZipFile(src)
            val outZip = ZipOutputStream(output.outputStream().buffered())

            srcZip.use { zin ->
                outZip.use { zout ->
                    val entries = zin.entries()
                    while (entries.hasMoreElements()) {
                        val entry = entries.nextElement()
                        val name = entry.name

                        if (name.endsWith(".dex") && byDex.containsKey(name)) {
                            // Patch this dex.
                            val patchedDex = patchDexEntry(zin.getInputStream(entry), byDex[name]!!, workDir, name)
                            zout.putNextEntry(ZipEntry(name))
                            patchedDex.inputStream().use { it.copyTo(zout) }
                            zout.closeEntry()
                        } else {
                            // Copy unchanged.
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
        } finally {
            // Keep output; clean intermediate smali/dex only.
            // (workDir removal is handled by caller or app cache cleanup.)
        }
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
        val assembleOk = Smali.assemble(smaliOpts, arrayOf(smaliDir.absolutePath))
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
        // Build path: smali/package/path/Name.smali (inner classes use '$').
        val pathParts = mutableListOf<String>()
        var i = 0
        while (i < parts.size) {
            // Inner class is denoted by '$'; keep it in the same file segment.
            val seg = parts[i]
            if (seg.contains('$')) {
                pathParts.add(seg)
                i++
            } else if (i < parts.size - 1) {
                pathParts.add(seg)
                i++
            } else {
                pathParts.add(seg)
                i++
            }
        }
        val fileName = pathParts.last() + ".smali"
        val dirs = pathParts.dropLast(1)
        // Also search recursively in case of package differences.
        val direct = File(File(smaliDir, dirs.joinToString("/")), fileName)
        if (direct.exists()) return direct
        // Fallback: recursive search by filename.
        return smaliDir.walkTopDown().firstOrNull { it.isFile && it.name == fileName }
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
