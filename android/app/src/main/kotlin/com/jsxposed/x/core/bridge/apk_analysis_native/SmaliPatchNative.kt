package com.jsxposed.x.core.bridge.apk_analysis_native

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * MethodChannel bridge for the "一键修改" (one-click smali modify) feature.
 *
 * Exposes:
 *   - `applySmaliPatch` : pick an APK + smali plans, patch, and write the new
 *     (unsigned) APK. The output is placed in a **user-accessible public
 *     location** (the app's public Downloads folder when possible) so the user
 *     can actually reach it with a file manager.
 *   - `shareApk`        : fire an ACTION_SEND chooser (via FileProvider) so the
 *     user can save/install the generated APK to any location/app.
 *
 * IMPORTANT: the patch pipeline is dispatched to a background thread so the UI
 * stays responsive; results are delivered back on the main thread.
 */
object SmaliPatchNative {
    private const val CHANNEL_NAME = "com.jsxposed.x/smali_patch"
    private const val FILE_PROVIDER_AUTHORITY = "com.jsxposed.x.fileprovider"
    private const val MAX_PARALLEL = 1

    private val executor: ExecutorService = Executors.newFixedThreadPool(MAX_PARALLEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var appContext: Context

    fun register(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "applySmaliPatch" -> {
                    val apkPath = call.argument<String>("apkPath") ?: ""
                    val raw = call.argument<String>("modificationsJson")
                    val modifications = parseModifications(raw)
                    executor.execute {
                        val outcome = runCatching {
                            val patchResult = SmaliPatcher.apply(apkPath, modifications, workDir())
                            val finalPath = moveToPublicLocation(patchResult.outputPath)
                            SmaliPatchResult(
                                outputPath = finalPath,
                                success = patchResult.success,
                                message = patchResult.message,
                            )
                        }
                        mainHandler.post {
                            outcome.onSuccess { p ->
                                result.success(mapOf(
                                    "outputPath" to p.outputPath,
                                    "success" to p.success,
                                    "message" to p.message,
                                ))
                            }.onFailure { e ->
                                result.error("smali_patch_error", e.message, null)
                            }
                        }
                    }
                }

                "shareApk" -> {
                    val path = call.argument<String>("apkPath") ?: ""
                    mainHandler.post {
                        try {
                            shareApk(context, path)
                            result.success(mapOf("shared" to true))
                        } catch (e: Exception) {
                            result.error("share_error", e.message, null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun workDir(): File = File(appContext.cacheDir, "smali_patch").apply { mkdirs() }

    /**
     * Move/copy the generated APK to a public, user-accessible folder:
     *  - If MANAGE_EXTERNAL_STORAGE is granted: write to
     *    /storage/emulated/0/Download/JsxposedX/modified_<name>.apk
     *  - Otherwise: fall back to the app's external files dir
     *    /storage/emulated/0/Android/data/<pkg>/files/... (still on public
     *    storage but app-scoped).
     */
    private fun moveToPublicLocation(srcPath: String): String {
        val src = File(srcPath)
        if (!src.exists()) return srcPath

        val publicDir = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                Environment.isExternalStorageManager()
            ) {
                File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "JsxposedX",
                ).also { it.mkdirs() }
            } else null
        } catch (_: Exception) { null }

        val destDir = publicDir ?: appContext.getExternalFilesDir(null) ?: appContext.cacheDir
        val dest = File(destDir, src.name)

        return try {
            src.copyTo(dest, overwrite = true)
            src.delete()
            dest.absolutePath
        } catch (e: Exception) {
            srcPath
        }
    }

    /** Fire an ACTION_SEND chooser so the user can save/install the APK anywhere. */
    private fun shareApk(context: Context, path: String) {
        val file = File(path)
        if (!file.exists()) throw ActivityNotFoundException("文件不存在: $path")
        val uri = FileProvider.getUriForFile(context, FILE_PROVIDER_AUTHORITY, file)

        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/vnd.android.package-archive"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, "保存/分享 修改后的 APK").apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
    }

    private fun parseModifications(raw: String?): List<SmaliModification> {
        if (raw.isNullOrBlank()) return emptyList()
        val arr = JSONArray(raw)
        val list = mutableListOf<SmaliModification>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            list.add(SmaliModification(
                dexPath = o.optString("dexPath", "classes.dex"),
                className = o.optString("className", ""),
                methodName = o.optString("methodName", ""),
                modifiedSmali = o.optString("modifiedSmali", ""),
            ))
        }
        return list
    }
}
