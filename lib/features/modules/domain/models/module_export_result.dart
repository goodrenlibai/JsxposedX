/// Result of exporting a single bundled module to a Magisk flashable zip.
class ModuleExportResult {
  const ModuleExportResult({
    required this.moduleId,
    required this.success,
    this.outputPath,
    this.bytesWritten,
    this.error,
    this.warnings = const [],
  });

  final String moduleId;
  final bool success;

  /// Absolute path of the written `.zip` file on success.
  final String? outputPath;

  /// Number of bytes written.
  final int? bytesWritten;

  /// Human-readable error message on failure.
  final String? error;

  /// Non-fatal warnings collected during export (e.g. a missing optional
  /// binary that will make the module non-functional on some devices).
  final List<String> warnings;

  factory ModuleExportResult.ok({
    required String moduleId,
    required String outputPath,
    required int bytesWritten,
    List<String> warnings = const [],
  }) {
    return ModuleExportResult(
      moduleId: moduleId,
      success: true,
      outputPath: outputPath,
      bytesWritten: bytesWritten,
      warnings: warnings,
    );
  }

  factory ModuleExportResult.fail({
    required String moduleId,
    required String error,
    List<String> warnings = const [],
  }) {
    return ModuleExportResult(
      moduleId: moduleId,
      success: false,
      error: error,
      warnings: warnings,
    );
  }
}

/// Live progress callback used while exporting a module.
typedef ModuleExportProgressCallback = void Function(
  int completed,
  int total,
  String currentFile,
);
