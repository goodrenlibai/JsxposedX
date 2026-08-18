# JsxposedX

- Frida module: [`jsxposedx-frida`](https://github.com/dugongzi/jsxposedx-frida)
- English: [`README_EN.md`](README_EN.md)
- 中文：[`README_CN.md`](README_CN.md)
- Release：[`Download`](https://jsxposed.org)
- 沐雪AI中转站[`前往`](https://api.muxueai.pro)
JsxposedX is a Flutter Android application for Xposed/LSPosed and Frida workflows.


This project has long adhered to free and open source sharing, aiming to lower the learning threshold and promote positive technology exchange

This project is an open source technical research tool, which is only used for legal purposes such as software debugging, program analysis, memory mechanism learning, development testing, and authorized environment research.

The author develops and publishes this project for the purpose of promoting technical exchange and learning, and does not provide any support for cheating, bypassing protection, or providing guidance on illegal use.

It is strictly prohibited to use the following acts:
• Cheating in online games, creating plug-ins, and automated illegal operations
• Interferes with the normal operation of the server or client
• Unauthorized modification of third-party program data
• Undermining the level playing field
• Any use that violates laws, regulations, or platform rules

Responsibility Description:

Users should ensure that their use of the service complies with local laws and regulations and relevant service terms. Any direct or indirect consequences arising from the use, dissemination, and secondary development of this project shall be borne by the user and have nothing to do with the author.

Open Source Notes:

The disclosure of the source code of this project does not encourage abuse. Any modification, distribution, commercialization, or illegal use by any third party based on this project has nothing to do with the original author's position.

The author reserves the right to:

The author has the right to refuse to provide support for any violating use and may adjust, suspend, or terminate the project's public content at any time.

By continuing to use this project, you are deemed to have read and agreed to this statement.

AI feature targeting

The built-in AI functions of this project are only used as general intelligent auxiliary modules, mainly used for data analysis, content interpretation, result screening, information organization, operation guidance, learning and research, and other scenarios to improve user efficiency and experience.

AI functions are auxiliary services and are not directly involved in the operation control, data destruction, permission bypass, cheat execution, or other illegal operations of any target program.

Built-in interface description

For user convenience, this project provides default AI interface access services. Users can also configure and use legally obtained third-party AI service interfaces according to their own needs, and there are no mandatory restrictions on this project.

Fee description

If some AI functions involve server resources, model call costs, computing power consumption, or interface fees, the project team may charge reasonable costs for related services. This fee only corresponds to the consumption of AI service resources and does not represent support or charges for any violating uses.

Output disclaimer

The AI output content is automatically generated based on the model and may contain errors, omissions, inaccuracies, or circumstances that may not be suitable for specific scenarios, and is for reference only. Users should make their own judgment and bear the responsibility for their final use.

Usage specifications

It is strictly prohibited to use the AI features of this project to engage in the following acts:
• Plugin production, cheat assistance, and automated illegal operations
• Hack, attack, or interfere with third-party systems
• Infringe on the legitimate rights and interests of others
• Violations of laws, regulations and platform rules

Attribution of responsibility

Any actions and consequences implemented by the user based on the AI functions of this project shall be borne by the user and have nothing to do with the project author.

Author's position

The author has always advocated for the use of AI technology in legal, legitimate, and positive learning research and efficiency improvement scenarios, and opposes any abuse.

## Summary

- Flutter UI with Android-side Xposed hooks, LSPosed service integration, and native bridge modules
- Project entries for `Quick Functions`, `AI Reverse`, `Xposed Project`, and `Frida Project`
- Additional pages for crypto audit and SO analysis
- Pigeon code generation via `.buildScript/pigen_watch.ps1`
- Debug install flow via `.buildScript/run_install_debug.ps1`
- Shared run configurations in `.idea/runConfigurations/`: `watch_pigeons` and `build_for_xposed_type`
## Build Note

This repository is not a normal Flutter-only app. Device-side verification also involves the Android/Xposed side, so the repository includes shared PowerShell scripts and shared IDE run configurations.

The Android module now uses two thin Xposed shells:

- `android/app/src/api100/` for the legacy `api100` shell
- `android/app/src/api101/` for the modern `api101` shell
- `android/app/src/main/` for shared Flutter/UI and hook core code

Default debug tasks still point to `api100`:

```powershell
.\.buildScript\run_install_debug.ps1
```

Install the `api101` shell explicitly with:

```powershell
.\.buildScript\run_install_debug.ps1 -GradleTask :app:installApi101Debug
```

Build/release note:

- `flutter build appbundle --flavor api100 --release` goes through the Flutter CLI first, then calls the matching Android variant
- `flutter build apk --flavor api101 --release` builds the corresponding release APK, for example `build/app/outputs/flutter-apk/app-api101-release.apk`
- `.\gradlew.bat :app:bundleApi100Release` goes directly through Android Gradle
- `.\gradlew.bat :app:assembleApi101Release` goes directly through Android Gradle for the matching release APK
- for the same flavor, both commands target the same Android release variant output

## CI Status

Android APK is built and published automatically by GitHub Actions (see `.github/workflows/build.yml`).
