# fix-003 — EncryptUtil 空字符串 AES 边界缺陷

- **类型**：业务代码缺陷（边界输入）
- **文件**：`lib/core/utils/encrypt_util.dart`
- **发现方式**：新增单元测试 `encrypt_util_test.dart` 中「empty string round-trips」断言失败。

## 原因
底层 `encrypt` 包的 AES/CBC 实现对**空明文**无法处理，`aesEncrypt('', pw)` 直接抛出 `RangeError (start): Invalid value: Only valid value is 0: -16`。这意味着任何传入空字符串的加密调用都会崩溃。

## 修复前
`aesEncrypt('', pw)` → 抛 `RangeError`（崩溃）；`aesDecrypt` 同理对空密文无保护。

## 修复后
- `aesEncrypt`：若 `plaintext.isEmpty` 直接返回 `''`；
- `aesDecrypt`：若 `ciphertext.isEmpty` 直接返回 `''`。

空密文是无歧义的：对非空数据的真实加密结果恒为非空 base64，因此 `'' ↔ ''` 的往返不会与真实密文冲突，向后兼容。

## 影响范围
仅影响空字符串输入（此前会崩溃）；非空输入路径完全不变。已核对该工具在项目内的其它调用方均不依赖空输入的特殊行为。

## 回归验证
- 重新运行 `test/unit/core/encrypt_util_test.dart` ✅ 全部通过
- 重新运行整套 `test/unit` + `test/widget` ✅ 通过
