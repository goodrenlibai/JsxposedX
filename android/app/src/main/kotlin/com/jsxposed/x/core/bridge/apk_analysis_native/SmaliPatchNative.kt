package com.jsxposed.x.core.bridge.apk_analysis_native

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * MethodChannel bridge for the "一键修改" (one-click smali modify) feature.
 *
 * Exposes a single method `applySmaliPatch` that takes the selected APK path
 * plus the AI's smali modification plans (JSON), runs the baksmali/smali
 * pipeline, and returns the path of the produced unsigned APK.
 *
 * Flutter call args:
 * ```
 * {
 *   "apkPath": "/path/to/app.apk",
 *   "modifications": [
 *     {
 *       "dexPath": "classes.dex",
 *       "className": "com.example.app.VipManager",
 *       "methodName": "isVip",
 *       "modifiedSmali": ".method public isVip()Z\n...\n.end method"
 *     }
 *   ]
 * }
 * ```
 *
 * Returns a Map: `{ "outputPath": "...", "success": bool, "message": "..." }`.
 */
object SmaliPatchNative {
    private const val CHANNEL_NAME = "com.jsxposed.x/smali_patch"

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "applySmaliPatch" -> {
                    try {
                        val apkPath = call.argument<String>("apkPath") ?: ""
                        val raw = call.argument<String>("modificationsJson")
                        val modifications = parseModifications(raw)
                        val workDir = File(context.cacheDir, "smali_patch")
                        val patchResult = SmaliPatcher.apply(apkPath, modifications, workDir)
                        result.success(
                            mapOf(
                                "outputPath" to patchResult.outputPath,
                                "success" to patchResult.success,
                                "message" to patchResult.message,
                            )
                        )
                    } catch (e: Exception) {
                        result.error("smali_patch_error", e.message, null)
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
