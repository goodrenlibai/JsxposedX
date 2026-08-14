# fix-002 — ZipWriter 非 ASCII 文件名编码缺陷

- **类型**：业务代码缺陷
- **文件**：`lib/core/utils/zip_writer.dart`
- **发现方式**：新增单元测试 `zip_writer_test.dart` 中「non-ASCII filenames round-trip」断言失败。

## 原因
`_utf8(String value)` 原实现使用 `value.codeUnits` 生成字节。Dart `String.codeUnits` 返回 **UTF-16 code units**，对中文等非 ASCII 字符会超过一个字节，而 `Uint8List.fromList` 会截断到低 8 位，产生**非法 UTF-8** 字节序列，同时文件头仍置 UTF-8 标志位，导致中文路径的 ZIP 条目无法被正确解析。

## 修复前
`_utf8('gadget/libgadget-中文.so.xz')` → 截断后的错误字节（非 UTF-8）。

## 修复后
`_utf8` 改为 `utf8.encode(value)`，生成标准 UTF-8 字节。

## 影响范围
仅影响 ZIP 归档中包含非 ASCII 文件名时（本项目内置模块 `jsxposedx-frida` 全部为 ASCII 文件名，故实际发布不受影响），属于健壮性修复，向后兼容。

## 回归验证
- 重新运行 `test/unit/core/zip_writer_test.dart` ✅ 全部通过
- 额外用系统 `unzip -t` 验证导出的模块 ZIP 结构 ✅
