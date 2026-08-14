/// A module that is bundled inside the app and can be exported by the user.
///
/// The module definition comes from `assets/modules/manifest.json`. Each
/// module points to a folder of assets under `assets/modules/<id>/` that
/// contains a Magisk-module package (module.prop, customize.sh, binaries...).
class BundledModule {
  const BundledModule({
    required this.id,
    required this.name,
    required this.version,
    required this.versionCode,
    required this.author,
    required this.description,
    required this.category,
    required this.flavor,
    required this.rootPath,
    required this.requiredAssets,
    required this.optionalAssets,
    required this.exportFileName,
  });

  final String id;
  final String name;
  final String version;
  final int versionCode;
  final String author;
  final String description;
  final String category;

  /// e.g. `zygisk` / `riru` / `xposed`
  final String flavor;

  /// Flutter asset prefix, e.g. `assets/modules/jsxposedx-frida`.
  final String rootPath;

  /// Files that must be present for a valid export.
  final List<String> requiredAssets;

  /// Binaries that are bundled when present (arch-dependent .so / gadget).
  final List<String> optionalAssets;

  /// Default file name for the exported Magisk zip.
  final String exportFileName;

  bool get isZygisk => category == 'zygisk';
}
