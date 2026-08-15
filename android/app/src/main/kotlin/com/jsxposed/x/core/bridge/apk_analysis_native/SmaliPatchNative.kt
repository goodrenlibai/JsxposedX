package com.jsxposed.x.core.bridge.apk_analysis_native

import android.content.Context
import android.os.Handler
import android.os.Looper
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
 * Exposes a single method `applySmaliPatch` that takes the selected APK path
 * plus the AI's smali modification plans (JSON), runs the baksmali/smali
 * pipeline, and returns the path of the produced unsigned APK.
 *
 * IMPORTANT: The baksmali/smali pipeline is very slow and memory-heavy (it
 * disassembles and reassembles the whole dex). It must NEVER run on the main
 * thread, otherwise the app freezes (ANR) and can be killed by the OS. So the
 * actual work is dispatched to a background [ExecutorService], and the result
 * is delivered back to Flutter on the main thread via a [Handler].
 *
 * Flutter call args:
 * ```
 * {
 *   "apkPath": "/path/to/app.apk",
 *   "modificationsJson": "[{\"dexPath\":\"classes.dex\",\"className\":\"com.x.Y\",\"methodName\":\"isVip\",\"modifiedSmali\":\".method ...\"}]"
 * }
 * ```
 *
 * Returns a Map: `{ "outputPath": "...", "success": bool, "message": "..." }`.
 */
object SmaliPatchNative {
    private const val CHANNEL_NAME = "com.jsxposed.x/smali_patch"
    private const val MAX_PARALLEL = 1 // serialize; dex reassembly is memory heavy

    private val executor: ExecutorService = Executors.newFixedThreadPool(MAX_PARALLEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "applySmaliPatch" -> {
                    val apkPath = call.argument<String>("apkPath") ?: ""
                    val raw = call.argument<String>("modificationsJson")
                    val modifications = parseModifications(raw)

                    // Run the heavy work on a background thread so the UI stays
                    // responsive, then deliver the reply back on the main thread.
                    executor.execute {
                        val outcome = runCatching {
                            val workDir = File(context.cacheDir, "smali_patch")
                            SmaliPatcher.apply(apkPath, modifications, workDir)
                        }
                        mainHandler.post {
                            outcome.onSuccess { patchResult ->
                                result.success(
                                    mapOf(
                                        "outputPath" to patchResult.outputPath,
                                        "success" to patchResult.success,
                                        "message" to patchResult.message,
                                    )
                                )
                            }.onFailure { e ->
                                result.error("smali_patch_error", e.message, null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun parseModifications(raw: String?): List<SmaliModification> {
        if (raw.isNullOrBlank()) return emptyList()
        val arr = JSONArray(raw)
        val list = mutableListOf<SmaliModification>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            list.add(
                SmaliModification(
                    dexPath = o.optString("dexPath", "classes.dex"),
                    className = o.optString("className", ""),
                    methodName = o.optString("methodName", ""),
                    modifiedSmali = o.optString("modifiedSmali", ""),
                )
            )
        }
        return list
    }
}
