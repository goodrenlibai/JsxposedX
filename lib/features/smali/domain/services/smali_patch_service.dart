import 'dart:convert';

import 'package:flutter/services.dart';

/// A single smali modification request derived from the AI plan.
class SmaliModificationRequest {
  final String dexPath;
  final String className;
  final String methodName;
  final String modifiedSmali;

  const SmaliModificationRequest({
    this.dexPath = 'classes.dex',
    required this.className,
    required this.methodName,
    required this.modifiedSmali,
  });

  Map<String, dynamic> toJson() => {
    'dexPath': dexPath,
    'className': className,
    'methodName': methodName,
    'modifiedSmali': modifiedSmali,
  };
}

/// Result of applying smali modifications to an APK.
class SmaliPatchResult {
  final String outputPath;
  final bool success;
  final String message;

  const SmaliPatchResult({
    required this.outputPath,
    required this.success,
    required this.message,
  });

  bool get isSuccess => success;
}

/// Flutter bridge to the native smali-patch MethodChannel
/// (`com.jsxposed.x/smali_patch`).
class SmaliPatchService {
  SmaliPatchService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.jsxposed.x/smali_patch');

  final MethodChannel _channel;

  /// Apply [modifications] to the APK at [apkPath], returning the path of the
  /// produced unsigned APK.
  Future<SmaliPatchResult> applySmaliPatch({
    required String apkPath,
    required List<SmaliModificationRequest> modifications,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'applySmaliPatch',
      {
        'apkPath': apkPath,
        'modificationsJson': jsonEncode(
          modifications.map((m) => m.toJson()).toList(),
        ),
      },
    );
    if (result == null) {
      throw StateError('smali patch 调用返回空结果');
    }
    return SmaliPatchResult(
      outputPath: (result['outputPath'] as String?) ?? '',
      success: (result['success'] as bool?) ?? false,
      message: (result['message'] as String?) ?? '',
    );
  }

  /// Fire a share/save chooser so the user can save/install the generated APK
  /// to any accessible location.
  Future<bool> shareApk({required String apkPath}) async {
    final ok = await _channel.invokeMethod<bool>('shareApk', {
      'apkPath': apkPath,
    });
    return ok ?? false;
  }
}
